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

## A Rome AI-only campaign (seed 4242) after 20 turns, all rules as they are.
const ROME_20 := "575e23d5"  # = HEAD 1c04fbe before the pack switch existed

var fails := 0


func _init() -> void:
	_rome_round_trip()
	_refusals()
	_hash_view()
	_west()
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
	_check(CData.pack == "west" and CData.region_count() == 32 and CData.faction_count() == 8, "use_pack(\"west\"): 32 regions, 8 factions")
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
