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
const CSea := preload("res://campaign/csea.gd")
const CStorm := preload("res://campaign/cstorm.gd")
const CCaptain := preload("res://campaign/ccaptain.gd")
const CAIFleet := preload("res://campaign/cai_fleet.gd")
const CLanes := preload("res://campaign/clanes.gd")
const CBattle := preload("res://campaign/cbattle.gd")
const SeaChecks := preload("res://tests/sea_checks.gd")

## A Rome AI-only campaign (seed 4242) after 20 turns, all rules as they are.
const ROME_20 := "2cd9a3eb"  # format 8 (Docking, 2026-10-23: was e588f4c3; SEA_AWAY_PCT 120 at Average, 2026-10-23: was e9ea81e2; Rome data: Syracuse start fleet, SEA_TRADE_PCT 50, 2026-10-23: was 65b64803; garrisons against landings, docs/AI.md 12.2, 2026-10-23: was a2def14b; Rome fleets, R2, 2026-10-23: was 91b91238; the AI's odds as win chances, docs/AI.md 12.1, 2026-10-22: was 244711de and 6fd1aac2 as format 7; the sea lanes pay in the income, 2026-10-22: was 70843c45 and 57aa56ba as format 7; fog-of-war memory; was 575e23d5, 2026-10-17; d60c218a until the auto-resolve refit, 3c26a0bc until the memory gained lvl / wl, 2026-10-22)
## The same play without the fog keys (CState.as_format 7) = HEAD 1c04fbe
## before the pack switch existed: the fog changes no rule.
const ROME_20_V7 := "9425a021"  # (635e25ce until Docking, 2026-10-23; 066b42cf until SEA_AWAY_PCT 120, 2026-10-23; 5a0bbec3 until the Rome data follow-up, 2026-10-23; a0016f69 until the garrisons against landings, 2026-10-23; 4a93a2f1 until Rome fleets, R2, 2026-10-23; 6fd1aac2 until the AI's odds as win chances, 2026-10-22; 57aa56ba until the lanes paid, 2026-10-22; 575e23d5 until the auto-resolve refit, 2026-10-22)

var fails := 0


func _init() -> void:
	_rome_round_trip()
	_refusals()
	_hash_view()
	_west()
	_fleets()
	_fleet_joins()
	_sea()
	_storms()
	_captains()
	_galleons()
	SeaChecks.campaign(_check)  # (N3a) a sea battle pending, fought, applied
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
	_check(CState.hash_text(b) == CState.hash_text(a) and CState.hash_text(a) == ROME_20
		and CState.hash_text(CState.as_format(a, 7)) == ROME_20_V7,
		"Rome after a switch round trip: the same golden (%s, %s; expected %s; as format 7 %s, expected %s)" % [CState.hash_text(a),
		CState.hash_text(b), ROME_20, CState.hash_text(CState.as_format(a, 7)), ROME_20_V7])
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
	_check(CState.hash_text(r) == ROME_20 and CState.hash_text(CState.as_format(r, 7)) == ROME_20_V7,
		"Rome golden after a West campaign (%s)" % CState.hash_text(r))
	# The lane caches follow the pack (CLanes' routes, tables and cell map are stamped with CData.gen).
	var rl := CLanes.lane(0)
	var rok := CLanes.count() == CData.SEA_LANES.size() and CLanes.total() == CData.SEA_LANES.size() and not rl.is_empty() \
		and CLanes.lanes_at(rl[rl.size() / 2]).has(0) and CLanes.base_value(r, 0) == (int(r["regions"][CLanes.ends(0)[0]]["level"]) + int(r["regions"][CLanes.ends(0)[1]]["level"])) * CData.LANE_BASE
	var jcell := -1
	for c in CLanes.cells_of(0):
		jcell = c
	CData.use_pack("west")
	var wl := CLanes.lane(0)
	var wok := CLanes.count() == CData.SEA_LANES.size() and CLanes.total() == CData.SEA_LANES.size() + CData.SEA_LANE_EXITS.size() \
		and wl != rl and not CLanes.lanes_at(wl[wl.size() / 2]).is_empty() and CLanes.exit_of(CData.region_index("havana")) >= 0
	CData.use_pack("rome")
	var rl2 := CLanes.lane(0)
	_check(rok and wok and rl2 == rl and CLanes.exit_of(0) < 0 and CLanes.lanes_at(jcell).has(0) and CSea.exit_cell() < 0,
		"the lane caches follow the pack: Rome's lanes are the same after a West switch and back")


## Fleets (N1, West only): Rome has none; the West start has fleets and
## shipyards and no sea lanes for armies; downwind reaches farther than
## upwind; an army boards, sails and lands; ships are launched; an
## interception is a sea battle, auto-resolved the same every time; a West
## state with troops aboard round-trips JSON with its hash.
func _fleets() -> void:
	CData.use_pack("rome")
	var rs := CState.new_campaign("r", 3, [])
	_check(CData.ships_on() and CData.CHAINS.size() == 8 and rs.has("fleets") and rs.has("next_fleet") and (rs["fleets"] as Array).size() == 8
		and CGrid.links(CGrid.port(CData.region_index("latium"))).size() > 0,
		"Rome (R2): ships on, eight building chains, eight start fleets, the sea lanes still link armies")
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
	# (N3a) England is a player: the sea battle is pending; auto-resolved
	# (the formula) it is the battle N1 resolved at once.
	var pend: Array = s2["battles"]
	_check(pend.size() == 1 and int(pend[0].get("sea", 0)) == 1 and CFleet.fleet(s2, 900).has("busy"),
		"with a player in it the sea battle is pending (%d battles)" % pend.size())
	for sx in [s2, s3]:
		if not (sx["battles"] as Array).is_empty():
			var pb: Dictionary = sx["battles"][0]
			CRules.apply_outcome(sx, int(pb["id"]), CBattle.formula(sx, pb))
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


## N2 (West only): a blockade cuts the port's income and pays the
## blockader; the flota's schedule is a function of the turn, it gathers the
## same twice and pays on arrival; a pirate assault sacks (gold taken, the
## owner keeps the town); a pirate faction with a ship and no region lives;
## a letter of marque is proposed, accepted, survives JSON and lapses.
func _sea() -> void:
	CData.use_pack("rome")
	var rs := CState.new_campaign("r", 3, [])
	CSea.update_blockades(rs)
	_check(not rs.has("marques") and CSea.marque_check(rs, 0, 1) != "" and not CSea.afloat(rs, 0)
		and (CData.ship_const("FLOTA_PARTS", []) as Array).is_empty() and not CStorm.on(rs) and not CCaptain.pack_on(),
		"Rome (R2): fleets and blockades on, no flota, letters, hurricanes or captains")
	CData.use_pack("west")
	var eng := CData.faction_index("england")
	var ns := CData.faction_index("new_spain")
	var tf := CData.faction_index("tierra_firme")
	var bret := CData.faction_index("brethren")
	var st := CState.new_campaign("w", 11, [eng], {}, [], "west")
	_check(CSea.pirate(bret) and not CSea.pirate(eng) and CSea.haven(st, CData.region_index("port_de_paix")),
		"the Brethren are pirates; Port-de-Paix is a haven")
	# Blockade: an English squadron off Campeche (New Spain's).
	var cp := CData.region_index("campeche")
	var hb := CFleet.harbour(cp)
	var sta := -1
	for c in CGrid.disc(hb, 3):
		if CFleet.is_sea(c) and CGrid.cheb(c, hb) == 3:
			sta = c
			break
	var sb := st.duplicate(true)
	sb["fleets"] = [{"id": 950, "f": eng, "x": CGrid.cx(sta), "y": CGrid.cy(sta), "ships": [{"t": "frigate", "h": 100, "c": 100}],
		"carry": [], "moved": 0}]
	var ns0 := int(CRules.income(sb, ns)["total"])
	var en0 := int(CRules.income(sb, eng)["total"])
	CSea.update_blockades(sb)
	var ns1 := CRules.income(sb, ns)
	var en1 := CRules.income(sb, eng)
	_check(CSea.blockader(sb, cp) == eng and int(ns1["blockaded"]) > 0 and int(ns1["total"]) < ns0
		and int(en1["plunder"]) > 0 and int(en1["total"]) == en0 + int(en1["plunder"]),
		"a blockade of Campeche: New Spain -%d a turn, England +%d" % [int(ns1.get("blockaded", 0)), int(en1.get("plunder", 0))])
	var ev := false
	for e in sb["events"]:
		if str(e["k"]) == "blockade" and int(e["r"]) == cp:
			ev = true
	(sb["fleets"][0] as Dictionary)["x"] = CGrid.cx(sta) + 30
	CSea.update_blockades(sb)
	_check(ev and CSea.blockader(sb, cp) < 0, "the blockade is announced, and lifted when the fleet sails off")
	# The flota.
	var first := CSea.k("FLOTA_FIRST", 4)
	_check(CSea.next_flota(st) == first, "the first flota is due on turn %d" % first)
	var sf := st.duplicate(true)
	sf["turn"] = first - 1
	var sf2 := sf.duplicate(true)
	CSea.flota_spawn(sf)
	CSea.flota_spawn(sf2)
	var parts: Array = []
	for fl in sf["fleets"]:
		if CSea.is_flota(fl):
			parts.append(fl)
	_check(parts.size() == 2 and CSea.treasure(parts[0]) > 0 and CState.hash_text(sf) == CState.hash_text(sf2)
		and CSea.next_flota(sf) == first and CSea.next_flota({"turn": first}) == first + CSea.k("FLOTA_EVERY", 8),
		"the flota gathers at Veracruz and Portobelo (%d parts, %d gold), the same twice" % [parts.size(),
			CSea.treasure(parts[0]) + (CSea.treasure(parts[1]) if parts.size() > 1 else 0)])
	var mv: Array = []
	CSea.flota_moves(sf, mv)
	_check(mv.size() == 2 and (int(mv[0][1]) == CSea.meet_cell() or not CLanes.lanes_at(int(mv[0][1])).is_empty())
		and (int(mv[1][1]) == CSea.meet_cell() or not CLanes.lanes_at(int(mv[1][1])).is_empty()),
		"the flota sails for Havana (along its lane's cells)")
	var gold := CSea.treasure(parts[0])
	var tre0 := int(sf["factions"][ns]["treasury"])
	CFleet.place(parts[0], CSea.exit_cell())
	parts[0]["flota"] = 2
	_check(CFleet.apply_order(sf, ns, {"t": "fcancel", "fleet": int(parts[0]["id"])}) != "", "the flota takes no orders")
	CSea.flota_arrivals(sf)
	_check(int(sf["factions"][ns]["treasury"]) == tre0 + gold and CFleet.fleet(sf, int(parts[0]["id"])).is_empty(),
		"the flota arrives off the map: New Spain +%d" % gold)
	# A treasure galleon taken pays its captor.
	var sp := st.duplicate(true)
	var open := CFleet.dock(CData.region_index("havana")) + 4
	var tg := {"id": 960, "f": ns, "x": CGrid.cx(open), "y": CGrid.cy(open) - 6, "flota": 0, "wait": 0,
		"ships": [{"t": "galleon", "h": 20, "c": 20, "g": 900, "o": tf}], "carry": [], "moved": 0}
	var hunter := {"id": 961, "f": bret, "x": CGrid.cx(open), "y": CGrid.cy(open) - 7, "ships": [{"t": "brigantine", "h": 100, "c": 100},
		{"t": "brigantine", "h": 100, "c": 100}, {"t": "brigantine", "h": 100, "c": 100}], "carry": [], "moved": 0}
	sp["fleets"] = [tg, hunter]
	var b0 := int(sp["factions"][bret]["treasury"])
	CFleet.resolve(sp, [hunter], [tg], CFleet.cell(tg))
	var sbt := {}
	for e in sp["events"]:
		if str(e["k"]) == "sea_battle":
			sbt = e
	_check(int(sbt.get("won", 1)) == 1 or int(sp["factions"][bret]["treasury"]) == b0 + int(sbt.get("gold", 0)),
		"a sea battle with a treasure galleon: prize money %d, galleons taken %d" % [int(sbt.get("gold", 0)), int(sbt.get("treasure", 0))])
	# A sack: the Brethren storm Campeche.
	var sk := st.duplicate(true)
	var pa: Dictionary = CState.armies_of(sk, bret)[0]
	pa["r"] = cp
	CState.place(pa, CState.ring_cell(cp, 0))
	var b := CRules.start_battle(sk, cp, pa)
	var nst0 := int(sk["factions"][ns]["treasury"])
	var bst0 := int(sk["factions"][bret]["treasury"])
	var lv0 := 0
	for sl in sk["regions"][cp]["slots"]:
		lv0 += int(sl[1])
	_check(CSea.sacks(sk, cp, bret), "the pirates' policy sacks a port they storm (%d regions)" % CState.regions_of(sk, bret).size())
	CRules.apply_outcome(sk, int(b["id"]), {"winner": 0, "mode": "formula", "units": [], "garrison_pct": 0})
	var lv1 := 0
	for sl in sk["regions"][cp]["slots"]:
		lv1 += int(sl[1])
	var sev := {}
	for e in sk["events"]:
		if str(e["k"]) == "sack":
			sev = e
	_check(CState.owner(sk, cp) == ns and not sev.is_empty() and int(sk["factions"][bret]["treasury"]) == bst0 + int(sev["gold"])
		and int(sev["gold"]) > 0 and int(sk["factions"][ns]["treasury"]) < nst0 and lv1 < lv0 and CSea.infamy(sk, bret) > 0
		and CSea.spared(sk, bret, cp),
		"a sack of Campeche: %d gold, buildings %d -> %d levels, New Spain keeps it, infamy %d" % [int(sev.get("gold", 0)), lv0, lv1, CSea.infamy(sk, bret)])
	sk["factions"][bret]["sack_pol"] = 2
	_check(not CSea.sacks(sk, cp, bret) and CRules.apply_order(sk, eng, {"t": "sack_policy", "v": 1}) != "",
		"the hold policy takes the port; only pirates set a policy")
	# Afloat: no region, a ship -> alive; no ship -> gone.
	var sa := st.duplicate(true)
	for r in CState.regions_of(sa, bret):
		sa["regions"][r]["owner"] = ns
	CRules.check_eliminations(sa)
	_check(CState.alive(sa, bret) and CSea.afloat(sa, bret), "a pirate faction without a region but with ships lives")
	var keep: Array = []
	for fl in sa["fleets"]:
		if int(fl["f"]) != bret:
			keep.append(fl)
	sa["fleets"] = keep
	CRules.check_eliminations(sa)
	_check(not CState.alive(sa, bret), "... and is gone with its last ship")
	# A letter of marque: England (a player at war with New Spain) to the
	# Brethren (AI).
	_check(CSea.marque_check(st, ns, bret) != "" and CSea.marque_check(st, eng, bret) == "" and CSea.marque_check(st, eng, ns) != "",
		"letters only between a nation and pirates; the Crown grants none")
	var orders: Array = [{"t": "propose", "to": bret, "what": "marque"}]
	var pv := CTurn.preview(st, eng, orders)
	_check((pv["errors"] as Array).is_empty(), "preview: a letter of marque proposal is valid")
	var sm := CTurn.resolve_turn(st, [CTurn.submission(st, eng, orders)])
	var mq := CSea.marque_of(sm, eng, bret)
	_check(not mq.is_empty() and CState.dip(sm, eng, bret) != CState.WAR and CSea.plunder_pct(sm, bret, ns) > 100,
		"the Brethren accept England's letter (until turn %d), at peace; plunder from New Spain at %d%%" % [int(mq[2]) if not mq.is_empty() else -1,
			CSea.plunder_pct(sm, bret, ns)])
	var js := CState.from_json(CState.to_json(sm))
	_check(not js.is_empty() and CState.hash_text(js) == CState.hash_text(sm) and CSea.has_marque(js, bret, eng),
		"a West state with a letter round-trips JSON (%s)" % CState.hash_text(sm))
	var sl2 := sm.duplicate(true)
	sl2["turn"] = int(mq[2]) if not mq.is_empty() else 0
	CSea.marque_turn(sl2)
	var sw := sm.duplicate(true)
	CRules.declare_war(sw, eng, bret)
	CSea.marque_turn(sw)
	_check(not CSea.has_marque(sl2, eng, bret) and not CSea.has_marque(sw, eng, bret), "the letter lapses at its turn, and war breaks it")
	CData.use_pack("rome")



## Fleets join by sailing (fmove with tgt = a fleet of ours): within a cell
## the merge is immediate (fmerge); farther the voyage is stored with `join`
## and carries on from turn to turn (the target's cell refreshed) until it
## merges; a lost target drops it; another faction's fleet is refused; fcancel
## clears it; JSON round trip and the same state on two clients.
func _fleet_joins() -> void:
	CData.use_pack("west")
	var eng := CData.faction_index("england")
	var st := CState.new_campaign("w", 11, [eng], {}, [], "west")
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
	_check(open >= 0, "joins: an open row of sea found")
	var fa := _fleet(900, eng, open, ["frigate"])
	var fb := _fleet(901, eng, CGrid.at(CGrid.cx(open) + 25, CGrid.cy(open)), ["sloop", "sloop"])
	var base := st.duplicate(true)
	base["fleets"] = [fa, fb]
	base["next_fleet"] = 902
	# Adjacent: fmerge (the tap) merges at once; ships and carry appended, source gone.
	var s0 := base.duplicate(true)
	CFleet.place(CFleet.fleet(s0, 900), CGrid.at(CGrid.cx(open) + 24, CGrid.cy(open)))
	(CFleet.fleet(s0, 900)["carry"] as Array).append({"id": 7777, "f": eng, "units": [], "r": 0})
	var wl := (CFleet.fleet(s0, 901)["ships"] as Array).size() + (CFleet.fleet(s0, 900)["ships"] as Array).size()
	_check(CFleet.apply_order(s0, eng, {"t": "fmerge", "fleet": 900, "into": 901}) == ""
		and CFleet.fleet(s0, 900).is_empty() and (CFleet.fleet(s0, 901)["ships"] as Array).size() == wl
		and (CFleet.fleet(s0, 901)["carry"] as Array).size() == 1,
		"joins: adjacent fmerge puts both fleets' ships in the target, the source gone")
	# Refusals.
	var other := -1
	for g in CData.FACTIONS.size():
		if g != eng and not CState.at_war(base, eng, g) and CState.alive(base, g):
			other = g
			break
	if other >= 0:
		var s1 := base.duplicate(true)
		(s1["fleets"] as Array).append(_fleet(950, other, CGrid.at(CGrid.cx(open) + 10, CGrid.cy(open)), ["sloop"]))
		_check(CFleet.apply_order(s1, eng, {"t": "fmove", "fleet": 900, "x": 0, "y": 0, "tgt": 950}) == "not our fleet",
			"joins: a fleet of a faction we are not at war with is refused (not our fleet)")
	_check(CFleet.apply_order(base.duplicate(true), eng, {"t": "fmove", "fleet": 900, "x": 0, "y": 0, "tgt": 900}) != ""
		and CFleet.apply_order(base.duplicate(true), eng, {"t": "fmove", "fleet": 900, "x": 0, "y": 0, "tgt": 12345}) != "",
		"joins: itself and a missing fleet are refused")
	var sf := base.duplicate(true)
	var fl_flota := _fleet(951, eng, CGrid.at(CGrid.cx(open) + 10, CGrid.cy(open)), ["galleon"])
	fl_flota["flota"] = 1
	(sf["fleets"] as Array).append(fl_flota)
	_check(CFleet.apply_order(sf, eng, {"t": "fmove", "fleet": 900, "x": 0, "y": 0, "tgt": 951}) != "", "joins: the flota is refused")
	# Sail to join, turn by turn.
	var orders: Array = [{"t": "fmove", "fleet": 900, "x": CGrid.cx(CFleet.cell(fb)), "y": CGrid.cy(CFleet.cell(fb)), "tgt": 901, "persist": 1}]
	var pv := CTurn.preview(base, eng, orders)
	_check((pv["errors"] as Array).is_empty(), "joins: the order previews valid %s" % str(pv["errors"]))
	var sub_a := CTurn.submission(base, eng, orders)
	var r1 := CTurn.resolve_turn(base, [sub_a])
	var r1b := CTurn.resolve_turn(base.duplicate(true), [CTurn.submission(base, eng, orders)])
	_check(CState.hash_text(r1) == CState.hash_text(r1b), "joins: two clients resolving the same submission agree (%s)" % CState.hash_text(r1))
	var a1 := CFleet.fleet(r1, 900)
	_check(not a1.is_empty() and int(a1.get("join", -1)) == 901 and a1.has("dest_x") and CFleet.voyage(a1)[1] == 901,
		"joins: turn 1 not adjacent, the voyage is stored with join %s" % str(a1.get("join", "-")))
	var js := CState.from_json(CState.to_json(r1))
	_check(not js.is_empty() and CState.hash_text(js) == CState.hash_text(r1) and int(CFleet.fleet(js, 900).get("join", -1)) == 901,
		"joins: the stored join survives the JSON round trip")
	var g := r1
	var turns := 1
	while not CFleet.fleet(g, 900).is_empty() and turns < 8:
		g = CTurn.resolve_turn(g, [CTurn.submission(g, eng, [])])
		turns += 1
	var merged := CFleet.fleet(g, 901)
	_check(CFleet.fleet(g, 900).is_empty() and not merged.is_empty() and (merged["ships"] as Array).size() == 3
		and turns >= 2, "joins: it arrives and merges by turn %d (3 ships, the target's id survives)" % turns)
	# The target sails away: the follower keeps following with the refreshed destination.
	var base2 := base.duplicate(true)
	var fa2 := _fleet(900, eng, CGrid.at(CGrid.cx(open) + 25, CGrid.cy(open)), ["galleon"])
	var fb2 := _fleet(901, eng, open, ["sloop", "sloop"])
	base2["fleets"] = [fa2, fb2]
	var run_orders: Array = [{"t": "fmove", "fleet": 900, "x": CGrid.cx(open), "y": CGrid.cy(open), "tgt": 901, "persist": 1},
		{"t": "fmove", "fleet": 901, "x": CGrid.cx(open) - 30, "y": CGrid.cy(open), "persist": 1}]
	var r2 := CTurn.resolve_turn(base2, [CTurn.submission(base2, eng, run_orders)])
	var a2 := CFleet.fleet(r2, 900)
	var b2 := CFleet.fleet(r2, 901)
	_check(not a2.is_empty() and not b2.is_empty() and int(a2.get("join", -1)) == 901
		and int(a2["dest_x"]) == CGrid.cx(open), "joins: the target sailed away, the follower keeps its join (dest %d,%d)" % [int(a2.get("dest_x", -1)), int(a2.get("dest_y", -1))])
	# Turn 2: the target turns round and sails back east; the follower sails to where it was
	# (the destination refreshed to the target's cell at the start of the turn) and still follows.
	var r2b := CTurn.resolve_turn(r2, [CTurn.submission(r2, eng, [{"t": "fmove", "fleet": 901, "x": CGrid.cx(open) + 30,
		"y": CGrid.cy(open), "persist": 0}])])
	var a2b := CFleet.fleet(r2b, 900)
	var b2b := CFleet.fleet(r2b, 901)
	_check(not a2b.is_empty() and not b2b.is_empty() and int(a2b.get("join", -1)) == 901 and int(a2b["dest_x"]) == int(b2["x"])
		and CGrid.cheb(CFleet.cell(a2b), CFleet.cell(b2b)) > 1,
		"joins: next turn the follower still follows, its destination refreshed (dest %d,%d, the target was at %d,%d)" % [int(a2b.get("dest_x", -1)), int(a2b.get("dest_y", -1)), int(b2["x"]), int(b2["y"])])
	# Target lost: the join is dropped, the fleet stays.
	var r3 := r1.duplicate(true)
	(r3["fleets"] as Array).erase(CFleet.fleet(r3, 901))
	var r3b := CTurn.resolve_turn(r3, [CTurn.submission(r3, eng, [])])
	var a3 := CFleet.fleet(r3b, 900)
	_check(not a3.is_empty() and not a3.has("join") and not a3.has("dest_x"), "joins: the target lost, the join is dropped and the fleet stays")
	# fcancel clears it.
	var r4 := r1.duplicate(true)
	_check(CFleet.apply_order(r4, eng, {"t": "fcancel", "fleet": 900}) == "" and not CFleet.fleet(r4, 900).has("join")
		and not CFleet.fleet(r4, 900).has("dest_x"), "joins: fcancel clears the stored join")
	var r4b := CTurn.resolve_turn(r4, [CTurn.submission(r4, eng, [])])
	_check(not CFleet.fleet(r4b, 900).is_empty() and not CFleet.fleet(r4b, 900).has("join"), "joins: a cancelled join does not come back")
	CData.use_pack("rome")


static func _fleet(id: int, f: int, c: int, ships: Array) -> Dictionary:
	var out: Array = []
	for t in ships:
		out.append({"t": str(t), "h": 100, "c": 100})
	return {"id": id, "f": f, "x": CGrid.cx(c), "y": CGrid.cy(c), "ships": out, "carry": [], "moved": 0}


## A sea cell within 6 of cell c, at least `away` (Chebyshev) from it and
## farther than CFleet.PORT_CELLS from every harbour (open water), -1 none.
static func _open_near(c: int, away: int) -> int:
	for j in CGrid.disc(c, 6):
		if not CFleet.is_sea(j) or CGrid.cheb(j, c) < away:
			continue
		var ok := true
		for r in CData.region_count():
			if CFleet.harbour(r) >= 0 and CGrid.cheb(CFleet.harbour(r), j) <= CFleet.PORT_CELLS + 1:
				ok = false
		if ok:
			return j
	return -1


## N2b hurricanes (West only): storms form only for the season and the same
## twice; a storm's move is deterministic and stays in its cone (or swerves
## a point); ships at sea in its core suffer far more than ships in port;
## a port in its path pays; the flota waits out a storm at Havana; an AI
## fleet in a cone runs out of it; JSON round trip.
func _storms() -> void:
	CData.use_pack("rome")
	var rs := CState.new_campaign("r", 3, [])
	_check(not CStorm.on(rs) and not rs.has("storms") and not rs.has("captains") and not rs.has("wrecks"), "Rome: no hurricanes, captains or wrecks")
	CData.use_pack("west")
	var eng := CData.faction_index("england")
	var ns := CData.faction_index("new_spain")
	var st := CState.new_campaign("w", 11, [eng], {}, [], "west")
	_check(CStorm.on(st) and CStorm.season(2) and not CStorm.season(3), "West: hurricanes, the season is the summer turn")
	# Formation: never for a winter turn; for a summer one the same twice.
	var sw := st.duplicate(true)
	sw["turn"] = 2
	CStorm.form(sw)
	var formed := 0
	var t1 := {}
	for t in [1, 3, 5, 7, 9, 11]:
		var a := st.duplicate(true)
		a["turn"] = t
		var b := a.duplicate(true)
		CStorm.form(a)
		CStorm.form(b)
		if CState.hash_text(a) != CState.hash_text(b):
			formed = -100
		formed += CStorm.storms(a).size()
		if t1.is_empty() and not CStorm.storms(a).is_empty():
			t1 = a
	_check(CStorm.storms(sw).is_empty() and formed > 0, "storms form only before a summer turn (%d in six seasons), the same twice" % formed)
	var box: Array = CData.ship_const("STORM_BOX", [])
	var s0: Dictionary = CStorm.storms(t1)[0] if not t1.is_empty() else {}
	_check(not s0.is_empty() and int(s0["px"]) / 100 >= int(box[0]) and int(s0["py"]) / 100 <= int(box[3]) and int(s0["h"]) in [12, 13],
		"a storm forms east of the Antilles heading west (%s)" % str(s0.get("nm", "")))
	# The track: deterministic, west-going, in its cone (or a point beyond).
	var a2 := t1.duplicate(true)
	var b2 := t1.duplicate(true)
	var old: Dictionary = (CStorm.storms(a2)[0] as Dictionary).duplicate(true)
	CStorm.strike_all(a2)
	CStorm.strike_all(b2)
	var moved: Dictionary = CStorm.storms(a2)[0] if not CStorm.storms(a2).is_empty() else {}
	var dh := posmod(int(moved.get("h", 0)) - int(old["h"]), 16)
	_check(CState.hash_text(a2) == CState.hash_text(b2) and not moved.is_empty() and int(moved["px"]) < int(old["px"])
		and dh in [0, 1, 2, 15] and (dh > 1 or CStorm.in_cone(old, CGrid.at(int(moved["px"]) / 100, int(moved["py"]) / 100))),
		"a storm's move is the same twice, westward, inside its cone or a point out (turned %d)" % dh)
	# Damage: twelve galleons at sea in the core against twelve in Havana.
	var hv := CData.region_index("havana")
	var dock := CFleet.dock(hv)
	var sea := _open_near(dock, 3)
	var sd := st.duplicate(true)
	var g12: Array = []
	for i in 12:
		g12.append("galleon")
	sd["fleets"] = [_fleet(970, ns, sea, g12), _fleet(971, ns, dock, g12)]
	var storm := {"id": 1, "px": CStorm.cpx(dock), "py": CStorm.cpy(dock), "h": 12, "v": 3000, "r": 6, "life": 2, "born": 0, "yr": 1650,
		"nm": "San Test", "tr": [], "lost": [], "ports": 0, "men": 0, "gold": 0}
	sd["storms"] = [storm]
	var tre0 := int(sd["factions"][ns]["treasury"])
	CStorm.strike(sd, storm, CStorm.cpx(dock), CStorm.cpy(dock), CStorm.cpx(sea), CStorm.cpy(sea))
	var hull := func(fl: Dictionary) -> int:
		var h := 0
		for sh in fl.get("ships", []):
			h += int(sh["h"])
		return h
	var at_sea: Dictionary = CFleet.fleet(sd, 970)
	var in_port: Dictionary = CFleet.fleet(sd, 971)
	var hs: int = hull.call(at_sea)
	var hp: int = hull.call(in_port)
	var ev := {}
	for e in sd["events"]:
		if str(e["k"]) == "storm_hit":
			ev = e
	_check(sea >= 0 and hs < hp and (at_sea.get("ships", []) as Array).size() <= (in_port["ships"] as Array).size(),
		"in the core twelve galleons at sea keep %d hull (%d ships), twelve in Havana %d (%d ships)" % [hs,
			(at_sea.get("ships", []) as Array).size(), hp, (in_port["ships"] as Array).size()])
	var hv_hit := false
	for pt in ev.get("ports", []):
		if int(pt[0]) == hv:
			hv_hit = true
	_check(hv_hit and int(sd["factions"][ns]["treasury"]) <= tre0, "Havana in its path pays (%d gold)" % (tre0 - int(sd["factions"][ns]["treasury"])))
	# The flota waits out a storm at Havana.
	var sf := st.duplicate(true)
	var ff := _fleet(980, ns, dock, ["galleon", "galleon"])
	ff["flota"] = 1
	ff["wait"] = 9
	(ff["ships"][0] as Dictionary)["g"] = 600
	sf["fleets"] = [ff]
	var calm := sf.duplicate(true)
	var near := storm.duplicate(true)
	near["px"] = CStorm.cpx(dock) + 1200
	near["py"] = CStorm.cpy(dock) + 400
	sf["storms"] = [near]
	var mv: Array = []
	CSea.flota_moves(sf, mv)
	var mv2: Array = []
	CSea.flota_moves(calm, mv2)
	var held := false
	for e in sf["events"]:
		if str(e["k"]) == "flota_held":
			held = true
	_check(mv.is_empty() and held and mv2.size() == 1, "the flota waits out a hurricane at Havana, and sails when it is calm")
	# An AI fleet in a cone runs out of it.
	var sa := st.duplicate(true)
	var ai := CData.faction_index("dutch")
	var open := _open_near(CFleet.dock(CData.region_index("santiago_de_cuba")), 5)
	sa["fleets"] = [_fleet(990, ai, open, ["frigate", "sloop"])]
	var cone := storm.duplicate(true)
	cone["px"] = CStorm.cpx(open) + 1500
	cone["py"] = CStorm.cpy(open)
	sa["storms"] = [cone]
	var mvs: Array = []
	var fm: Array = []
	CAIFleet.act(sa, ai, mvs, fm)
	var to := int(fm[0][1]) if not fm.is_empty() else -1
	_check(CStorm.danger(sa, open) and to >= 0 and not CStorm.danger(sa, to), "an AI fleet in a storm's cone runs for clear water or port")
	var js := CState.from_json(CState.to_json(sd))
	_check(not js.is_empty() and CState.hash_text(js) == CState.hash_text(sd), "a West state with a storm round-trips JSON")
	CData.use_pack("rome")


## N2b notorious captains: the Brethren's start fleets sail under named
## captains; fame grows with a won fight and its prizes; a captain whose
## fleet is destroyed meets his fate (a bounty for a famous one) and a new
## one rises; the more famous commands a merged fleet; fear adds power.
func _captains() -> void:
	CData.use_pack("west")
	var eng := CData.faction_index("england")
	var bret := CData.faction_index("brethren")
	var st := CState.new_campaign("w", 11, [eng], {}, [], "west")
	var bf := CFleet.fleets_of(st, bret)
	var names := {}
	for fl in bf:
		var c := CCaptain.of_fleet(st, int(fl["id"]))
		if not c.is_empty():
			names[str(c["nm"])] = 1
	_check(bf.size() >= 2 and names.size() == bf.size(), "the Brethren's %d start fleets have %d named captains (%s)" % [bf.size(), names.size(), ", ".join(names.keys())])
	# Fame: a pirate squadron beats a battered English sloop and takes it.
	var open := _open_near(CFleet.dock(CData.region_index("port_royal")), 5)
	var sb := st.duplicate(true)
	var pf := _fleet(int(bf[0]["id"]), bret, open, ["brigantine", "brigantine", "brigantine", "brigantine"])
	var prey := _fleet(800, eng, open + 1, ["sloop", "sloop"])
	for sh in prey["ships"]:
		sh["h"] = 30
	sb["fleets"] = [pf, prey]
	var cap: Dictionary = CCaptain.of_fleet(sb, int(pf["id"]))
	CFleet.resolve(sb, [pf], [prey], open)
	_check(not cap.is_empty() and int(cap["fame"]) > 0, "%s wins a sea fight: fame %d (%d prizes)" % [str(cap.get("nm", "")), int(cap.get("fame", 0)), int(cap.get("pz", 0))])
	# Death and succession: a famous captain's sloop is caught by a squadron.
	var sd := st.duplicate(true)
	var doomed := _fleet(int(bf[0]["id"]), bret, open, ["sloop"])
	(doomed["ships"][0] as Dictionary)["h"] = 5
	var navy := _fleet(801, eng, open + 1, ["ship_of_the_line", "ship_of_the_line", "frigate"])
	var others: Array = [doomed, navy]
	for fl in CFleet.fleets(sd):
		if int(fl["f"]) == bret and int(fl["id"]) != int(doomed["id"]):
			others.append(fl)
	others.sort_custom(func(x, y): return int(x["id"]) < int(y["id"]))
	sd["fleets"] = others
	var dc: Dictionary = CCaptain.of_fleet(sd, int(doomed["id"]))
	dc["fame"] = 60
	var nm := str(dc["nm"])
	var tre0 := int(sd["factions"][eng]["treasury"])
	CFleet.resolve(sd, [navy], [doomed], open)
	var fate := {}
	for e in sd["events"]:
		if str(e["k"]) == "captain_fate":
			fate = e
	var still := false
	for c in CCaptain.all(sd):
		if str(c["nm"]) == nm:
			still = int(c["fl"]) < 0
	var how := str(fate.get("how", ""))
	_check(CFleet.fleet(sd, int(doomed["id"])).is_empty() and not fate.is_empty()
		and (how in ["killed", "hanged"]) == (int(sd["factions"][eng]["treasury"]) == tre0 + int(fate.get("bounty", -1)))
		and (how in ["escaped", "ransomed"]) == still,
		"his fleet destroyed, %s was %s (bounty %d)" % [nm, how, int(fate.get("bounty", 0))])
	var fresh := _fleet(int(sd["next_fleet"]), bret, CFleet.dock(CData.region_index("port_de_paix")), ["sloop"])
	sd["next_fleet"] = int(fresh["id"]) + 1
	(sd["fleets"] as Array).append(fresh)
	for i in 30:
		if CCaptain.of_fleet(sd, int(fresh["id"])).is_empty():
			CCaptain.rise(sd)
	var nc := CCaptain.of_fleet(sd, int(fresh["id"]))
	var uniq := {}
	for c in CCaptain.all(sd):
		uniq[str(c["nm"])] = 1
	_check(not nc.is_empty() and uniq.size() == CCaptain.all(sd).size(), "a new fleet finds a captain: %s" % str(nc.get("nm", "")))
	# Merge: the more famous commands.
	var sm := st.duplicate(true)
	var f1: Dictionary = CFleet.fleets_of(sm, bret)[0]
	var f2: Dictionary = CFleet.fleets_of(sm, bret)[1]
	CFleet.place(f2, CFleet.cell(f1))
	var c1 := CCaptain.of_fleet(sm, int(f1["id"]))
	var c2 := CCaptain.of_fleet(sm, int(f2["id"]))
	c1["fame"] = 10
	c2["fame"] = 30
	_check(CFleet.apply_order(sm, bret, {"t": "fmerge", "fleet": int(f2["id"]), "into": int(f1["id"])}) == ""
		and int(c2["fl"]) == int(f1["id"]) and int(c1["fl"]) == -1, "merged fleets: the more famous captain commands, the other goes ashore")
	var p0 := CFleet._side_power(sm, [f1], false)
	c2["fame"] = 80
	_check(CFleet._side_power(sm, [f1], false) > p0, "a Legend's fleet counts more in a sea fight (fear)")
	var js := CState.from_json(CState.to_json(sd))
	_check(not js.is_empty() and CState.hash_text(js) == CState.hash_text(sd), "a West state with captains round-trips JSON")
	CData.use_pack("rome")


## N2b named treasure galleons: every flota galleon has a name (none
## twice), one capitana carries the big chest; infamous pirates bring
## escorts; taking a named one is a headline; a sunk one leaves a wreck.
func _galleons() -> void:
	CData.use_pack("west")
	var eng := CData.faction_index("england")
	var bret := CData.faction_index("brethren")
	var ns := CData.faction_index("new_spain")
	var st := CState.new_campaign("w", 11, [eng], {}, [], "west")
	var sf := st.duplicate(true)
	sf["turn"] = CSea.k("FLOTA_FIRST", 4) - 1
	CSea.flota_spawn(sf)
	var names := {}
	var n := 0
	var caps := 0
	var big := 0
	for fl in sf["fleets"]:
		if not CSea.is_flota(fl):
			continue
		for sh in fl["ships"]:
			if str(sh["t"]) == "galleon":
				n += 1
				names[str(sh.get("nm", ""))] = 1
				if int(sh.get("cap", 0)) != 0:
					caps += 1
					big = int(sh["g"])
	_check(n >= 2 and names.size() == n and not names.has("") and caps == 1 and big == CSea.k("FLOTA_CAPITANA_GOLD", 0),
		"the flota's %d galleons are named (%s), one capitana with %d" % [n, ", ".join(names.keys()), big])
	var se := st.duplicate(true)
	se["turn"] = CSea.k("FLOTA_FIRST", 4) - 1
	se["factions"][bret]["infamy"] = 70
	CSea.flota_spawn(se)
	var frig := 0
	for fl in se["fleets"]:
		if CSea.is_flota(fl):
			for sh in fl["ships"]:
				if str(sh["t"]) == "frigate":
					frig += 1
	_check(frig == 4, "infamous pirates (70): the Crown sends two escort frigates with each part (%d)" % frig)
	var sp := sf.duplicate(true)
	var gal := {}
	for fl in sp["fleets"]:
		if CSea.is_flota(fl):
			for sh in fl["ships"]:
				if int(sh.get("cap", 0)) != 0:
					gal = sh
	CSea.prize_money(sp, bret, ns, [gal], CFleet.dock(CData.region_index("havana")), "\"Test\" Tom")
	var head := {}
	for e in sp["events"]:
		if str(e["k"]) == "galleon_taken":
			head = e
	_check(str(head.get("nm", "")) == str(gal.get("nm", "?")) and int(head.get("cap", 0)) == 1 and str(head.get("capt", "")) == "\"Test\" Tom",
		"taking the capitana is a headline: the %s" % str(head.get("nm", "")))
	CSea.wreck(sp, gal, CFleet.dock(CData.region_index("havana")), "storm", -1)
	var wr: Array = sp.get("wrecks", [])
	_check(wr.size() == 1 and int(wr[0][3]) == int(gal["g"]) and str(wr[0][4]) == str(gal["nm"]), "a sunk treasure galleon leaves a wreck with her name")
	CData.use_pack("rome")
