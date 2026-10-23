class_name CSight
extends RefCounted
## Fog of war on the overworld (state format 8; docs/CAMPAIGN.md "Fog of
## war"). Pure functions of the state: what a faction's team sees this turn
## (computed, never stored) and what each faction remembers of what it saw
## (stored per faction, written by update_memory at the end of every turn).
##
## Sight (Rome 2 style), the union over the factions of f's team:
##   - its regions and their land neighbours (CData.adjacent, land routes):
##     every cell of those regions;
##   - each army: the cells within ARMY_R (Chebyshev) of its cell, HILL_R
##     when it stands on a hill / ridge cell (CGrid.cell_terrain);
##   - each fleet: FLEET_R (5, a masthead lookout on open water; 3 before 2026-10-23) around its sea cell (the armies aboard ride with
##     it and see nothing more);
##   - each character not riding with an army: CHAR_R around his city;
##   - each settlement it owns: CITY_R around the settlement cell (sea cells
##     too: a coastal city watches its waters);
##   - each coastal region it owns: the sea cells within COAST_R of any of
##     its coast cells (a cell of the region with a sea cell beside it), its
##     own sea; COAST_PORT_R when the region has a harbour (a pack with ships)
##     or walls 3 (a fort). Sea cells only: the enemy's coast stays dark.
## The AI sees everything (nothing in the AI reads this file); the rules
## never consult sight, so the fog changes nothing but what a player is
## shown.
##
## Memory (factions[f]["mem"], format 8): {"own": [last-known owner per
## region, -1 never seen], "turn": [turn of that look per region, -1],
## "mk": [last-seen markers {cell, f, kind (0 army / 1 fleet), units,
## turn, name}] sorted by cell, at most one per cell, at most MAX_MARKERS
## (the oldest dropped first); optional "lvl" / "wl": the settlement level and
## the walls level as last seen per region (-1 never seen; the keys absent in a
## memory written before they existed = unknown, no version bump)}. A marker is written for every foreign army /
## fleet in sight at the end of a turn (several on one cell: one marker, the
## first's faction and name, their units summed) and dropped when its cell
## is in sight again. Integers and index order only; no Dictionary is
## iterated.
##
## States older than format 8 have no fog: everything is in sight and
## update_memory leaves them alone (an unmigrated online campaign keeps its
## rules exactly).

const CData := preload("res://campaign/cdata.gd")
const CState := preload("res://campaign/cstate.gd")
const CGrid := preload("res://campaign/cgrid.gd")
const CRules := preload("res://campaign/crules.gd")
const CFleet := preload("res://campaign/cfleet.gd")
const Terrain := preload("res://sim/terrain.gd")

const VERSION_FOG := 8
const ARMY_R := 1
const HILL_R := 2
const FLEET_R := 5
const CHAR_R := 1
const CITY_R := 2
const COAST_R := 2
const COAST_PORT_R := 3
const MAX_MARKERS := 400

## View-side memo of the last visible() call (not used by update_memory):
## the state's reference, the faction and a cheap signature of everything
## sight reads.
static var _m_st = null
static var _m_f := -999
static var _m_sig := PackedInt64Array()
static var _m_vis := PackedByteArray()


## Every query below takes an optional last argument `vis`: the caller's
## copy of visible(st, f) (a view drawing many pieces passes its cached one).

## Fog applies to state st (format 8 and later).
static func on(st: Dictionary) -> bool:
	return int(st.get("version", 0)) >= VERSION_FOG


## The campaign's fog setting (0 off, 1 on; the view reads it: off shows
## everything). Memory is kept either way.
static func fog_setting(st: Dictionary) -> int:
	return int(st.get("fog", 1))


# ------------------------------------------------------------- sight ---

## One byte per grid cell (CGrid index order): 1 in sight of faction f's
## team this turn, 0 not. A state of an older format: all 1.
static func visible(st: Dictionary, f: int) -> PackedByteArray:
	var sig := _signature(st, f)
	if _m_st != null and is_same(_m_st, st) and _m_f == f and _m_sig == sig:
		return _m_vis
	var vis := compute(st, f)
	_m_st = st
	_m_f = f
	_m_sig = sig
	_m_vis = vis
	return vis


## visible() without the memo (the rules use this).
static func compute(st: Dictionary, f: int) -> PackedByteArray:
	CGrid.ensure()
	var n := CGrid.count()
	var vis := PackedByteArray()
	vis.resize(n)
	if not on(st):
		vis.fill(1)
		return vis
	vis.fill(0)
	if f < 0 or f >= CState.nf():
		return vis
	var mine := PackedByteArray()  # factions of f's team
	mine.resize(CState.nf())
	for g in CState.nf():
		mine[g] = 1 if CState.same_team(st, f, g) else 0
	# Regions: our own and their land neighbours.
	var nr := CData.region_count()
	var seen_r := PackedByteArray()
	seen_r.resize(nr)
	for r in nr:
		var o := CState.owner(st, r)
		if o < 0 or mine[o] == 0:
			continue
		seen_r[r] = 1
		for e in CData.adjacent(r):
			if int(e[1]) == 0:
				seen_r[int(e[0])] = 1
	for r in nr:
		if seen_r[r] != 0:
			for c in CGrid.cells_of(r):
				vis[c] = 1
	# Settlements.
	for r in nr:
		var o := CState.owner(st, r)
		if o >= 0 and mine[o] != 0:
			_square(vis, CGrid.site(r), CITY_R)
	# Coasts: an owned coastal region's own sea.
	for r in nr:
		var o := CState.owner(st, r)
		if o >= 0 and mine[o] != 0:
			for c in _halo(r, COAST_PORT_R if _port_or_fort(st, r) else COAST_R):
				vis[c] = 1
	# Armies (on the grid).
	if CState.grid_on(st):
		for a in st["armies"]:
			var af := int(a["f"])
			if af < 0 or af >= mine.size() or mine[af] == 0:
				continue
			var c := CState.cell(a)
			var rad := ARMY_R
			var k := CGrid.cell_terrain(c)
			if k == Terrain.K_HILL or k == Terrain.K_RIDGE:
				rad = HILL_R
			_square(vis, c, rad)
	# Fleets.
	for fl in st.get("fleets", []):
		var ff := int(fl["f"])
		if ff >= 0 and ff < mine.size() and mine[ff] != 0:
			_square(vis, int(fl["y"]) * CGrid.width() + int(fl["x"]), FLEET_R)
	# Characters in a city (the attached ones see with their army).
	for ch in st.get("chars", []):
		var cf := int(ch["f"])
		if int(ch["army"]) < 0 and cf >= 0 and cf < mine.size() and mine[cf] != 0:
			var r := int(ch["r"])
			if r >= 0 and r < nr:
				_square(vis, CGrid.site(r), CHAR_R)
	return vis


## The sight a query uses: the caller's (the view's cached visible(st, f),
## to skip the memo's fingerprint in a loop), else visible().
static func _vis(st: Dictionary, f: int, vis: PackedByteArray) -> PackedByteArray:
	return vis if vis.size() == CGrid.count() else visible(st, f)


## Region r has a harbour (a pack with ships) or walls 3 (a fort): its sea reaches COAST_PORT_R.
static func _port_or_fort(st: Dictionary, r: int) -> bool:
	return (CData.ships_on() and CFleet.harbour(r) >= 0) or CState.walls(st, r) >= 3


static var _halo_key := ""
static var _halos := {}   # r * 8 + rad -> the sea cells within rad (Chebyshev) of a coast cell of region r, in index order


## The sea cells within rad of any coast cell of region r (a cell of r with a sea cell among its 8 neighbours),
## ascending; empty for an inland region. Static grid data, built once per region and radius.
static func _halo(r: int, rad: int) -> PackedInt32Array:
	CGrid.ensure()
	var key := "%s_%d_%d" % [CData.pack, CGrid.count(), CGrid.width()]
	if key != _halo_key:
		_halo_key = key
		_halos = {}
	var k := r * 8 + rad
	if _halos.has(k):
		return _halos[k]
	var w := CGrid.width()
	var h := CGrid.height()
	var mark := PackedByteArray()
	mark.resize(CGrid.count())
	for c in CGrid.cells_of(r):
		var x0 := CGrid.cx(c)
		var y0 := CGrid.cy(c)
		var coast := false
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var j := CGrid.at(x0 + dx, y0 + dy)
				if j >= 0 and CGrid.region(j) == -1:
					coast = true
		if not coast:
			continue
		for y in range(maxi(y0 - rad, 0), mini(y0 + rad, h - 1) + 1):
			for x in range(maxi(x0 - rad, 0), mini(x0 + rad, w - 1) + 1):
				if CGrid.region(y * w + x) == -1:
					mark[y * w + x] = 1
	var out := PackedInt32Array()
	for i in mark.size():
		if mark[i] != 0:
			out.append(i)
	_halos[k] = out
	return out


static func _square(vis: PackedByteArray, c: int, rad: int) -> void:
	if c < 0:
		return
	var x0 := CGrid.cx(c)
	var y0 := CGrid.cy(c)
	var w := CGrid.width()
	var h := CGrid.height()
	for y in range(maxi(y0 - rad, 0), mini(y0 + rad, h - 1) + 1):
		for x in range(maxi(x0 - rad, 0), mini(x0 + rad, w - 1) + 1):
			vis[y * w + x] = 1


## Any cell of region r in sight of f's team.
static func region_visible(st: Dictionary, f: int, r: int, vis: PackedByteArray = PackedByteArray()) -> bool:
	if not on(st):
		return true
	return _region_seen(_vis(st, f, vis), r)


static func _region_seen(vis: PackedByteArray, r: int) -> bool:
	if r < 0 or r >= CData.region_count():
		return false
	for c in CGrid.cells_of(r):
		if vis[c] != 0:
			return true
	# (a region whose cells are all claimed by others: its settlement cell)
	var s := CGrid.site(r)
	return s >= 0 and vis[s] != 0


## The owner of region r as f last saw it (-1 never seen); the true owner
## when it is in sight (or the state has no fog).
static func known_owner(st: Dictionary, f: int, r: int, vis: PackedByteArray = PackedByteArray()) -> int:
	var mem := _mem(st, f)
	if mem.is_empty() or region_visible(st, f, r, vis):
		return CState.owner(st, r)
	return int(mem["own"][r])


## The turn of that last look (-1 never seen; this turn when in sight).
static func known_turn(st: Dictionary, f: int, r: int, vis: PackedByteArray = PackedByteArray()) -> int:
	var mem := _mem(st, f)
	if mem.is_empty() or region_visible(st, f, r, vis):
		return int(st.get("turn", 0))
	return int(mem["turn"][r])


## The settlement level of region r as f last saw it (-1 never seen or not
## recorded); the true level when in sight (or the state has no fog).
static func known_level(st: Dictionary, f: int, r: int, vis: PackedByteArray = PackedByteArray()) -> int:
	var mem := _mem(st, f)
	if mem.is_empty() or region_visible(st, f, r, vis):
		return int(st["regions"][r]["level"])
	return int((mem.get("lvl", []) as Array)[r]) if (mem.get("lvl", []) as Array).size() > r else -1


## The walls level of region r as f last saw it (same rules as known_level).
static func known_walls(st: Dictionary, f: int, r: int, vis: PackedByteArray = PackedByteArray()) -> int:
	var mem := _mem(st, f)
	if mem.is_empty() or region_visible(st, f, r, vis):
		return CState.walls(st, r)
	return int((mem.get("wl", []) as Array)[r]) if (mem.get("wl", []) as Array).size() > r else -1


## Last-seen army / fleet markers outside f's sight now, in cell order:
## [{"cell", "f", "kind" (0 army, 1 fleet), "units", "turn", "name"}]
## (copies; markers of f's own team are left out).
static func markers(st: Dictionary, f: int, vis_in: PackedByteArray = PackedByteArray()) -> Array:
	var mem := _mem(st, f)
	var out: Array = []
	if mem.is_empty():
		return out
	var vis := _vis(st, f, vis_in)
	for m in mem["mk"]:
		var c := int(m["cell"])
		if c < 0 or c >= vis.size() or vis[c] != 0 or CState.same_team(st, f, int(m["f"])):
			continue
		out.append((m as Dictionary).duplicate())
	return out


## Army st["armies"][army_index] is shown to f (its team's own always).
static func army_visible(st: Dictionary, f: int, army_index: int, vis: PackedByteArray = PackedByteArray()) -> bool:
	var arr: Array = st["armies"]
	if army_index < 0 or army_index >= arr.size():
		return false
	var a: Dictionary = arr[army_index]
	if not on(st) or CState.same_team(st, f, int(a["f"])) or not CState.grid_on(st):
		return true
	return _vis(st, f, vis)[CState.cell(a)] != 0


## Fleet st["fleets"][fleet_index] is shown to f.
static func fleet_visible(st: Dictionary, f: int, fleet_index: int, vis: PackedByteArray = PackedByteArray()) -> bool:
	var arr: Array = st.get("fleets", [])
	if fleet_index < 0 or fleet_index >= arr.size():
		return false
	var fl: Dictionary = arr[fleet_index]
	if not on(st) or CState.same_team(st, f, int(fl["f"])):
		return true
	return _vis(st, f, vis)[int(fl["y"]) * CGrid.width() + int(fl["x"])] != 0


## Character st["chars"][char_index] is shown to f: with his army when he
## rides with one (aboard a fleet: the fleet's cell), else at his city.
static func char_visible(st: Dictionary, f: int, char_index: int, vis_in: PackedByteArray = PackedByteArray()) -> bool:
	var arr: Array = st.get("chars", [])
	if char_index < 0 or char_index >= arr.size():
		return false
	var ch: Dictionary = arr[char_index]
	if not on(st) or CState.same_team(st, f, int(ch["f"])):
		return true
	var vis := _vis(st, f, vis_in)
	var id := int(ch["army"])
	if id >= 0:
		var i := CState.army_index(st, id)
		if i >= 0:
			return army_visible(st, f, i, vis)
		for fl in st.get("fleets", []):
			for a in fl["carry"]:
				if int(a["id"]) == id:
					return vis[int(fl["y"]) * CGrid.width() + int(fl["x"])] != 0
		return false
	var r := int(ch["r"])
	return r >= 0 and r < CData.region_count() and vis[CGrid.site(r)] != 0


## Battle bid is shown to f: a human of f's team fights in it, or its cell
## is in sight.
static func battle_visible(st: Dictionary, f: int, bid: int, vis: PackedByteArray = PackedByteArray()) -> bool:
	var b := CState.battle(st, bid)
	if b.is_empty():
		return false
	if not on(st):
		return true
	for h in CRules.battle_humans(st, b):
		if CState.same_team(st, f, int(h)):
			return true
	var side := CRules.battle_factions(st, b)
	for s in 2:
		for g in side[s]:
			if CState.same_team(st, f, int(g)):
				return true
	return _vis(st, f, vis)[battle_cell(b)] != 0


## Battle b's cell (its x, y; else its settlement's).
static func battle_cell(b: Dictionary) -> int:
	if b.has("x"):
		return CGrid.at(int(b["x"]), int(b["y"]))
	return CGrid.site(int(b["r"]))


# ------------------------------------------------------ view filters ---
## The rules' lists as faction `viewer` may see them (the view's lists and
## panels; the rules and the AI keep the unfiltered ones). Same results as
## the rules' own when the state has no fog.

## Pending battles shown to viewer (battle_visible), in state order.
static func battles_for(st: Dictionary, viewer: int, vis: PackedByteArray = PackedByteArray()) -> Array:
	var out: Array = []
	for b in st["battles"]:
		if battle_visible(st, viewer, int(b["id"]), vis):
			out.append(b)
	return out


## Armies filtered to those shown to viewer (state order kept).
static func shown_armies(st: Dictionary, viewer: int, list: Array, vis: PackedByteArray = PackedByteArray()) -> Array:
	if not on(st):
		return list.duplicate()
	var v := _vis(st, viewer, vis)
	var out: Array = []
	for a in list:
		if CState.same_team(st, viewer, int(a["f"])) or not CState.grid_on(st) or v[CState.cell(a)] != 0:
			out.append(a)
	return out


## CState.armies_in as viewer sees it.
static func armies_in_for(st: Dictionary, r: int, viewer: int, vis: PackedByteArray = PackedByteArray()) -> Array:
	return shown_armies(st, viewer, CState.armies_in(st, r), vis)


## CRules.hostile_field (the enemies of f in the field in region r) as
## viewer sees them.
static func hostile_field_for(st: Dictionary, r: int, f: int, viewer: int, vis: PackedByteArray = PackedByteArray()) -> Array:
	return shown_armies(st, viewer, CRules.hostile_field(st, r, f), vis)


## CRules.zone_armies (enemy armies with a zone of control) as f sees them.
static func zone_armies_for(st: Dictionary, f: int, vis: PackedByteArray = PackedByteArray()) -> Array:
	return shown_armies(st, f, CRules.zone_armies(st, f), vis)


## CRules.raider (the faction raiding region r, -1) as viewer sees it: -1
## unless one of that faction's armies raiding there is in sight (raiders
## in viewer's team's own lands always are: the lands are in sight).
static func raider_for(st: Dictionary, r: int, viewer: int, vis: PackedByteArray = PackedByteArray()) -> int:
	var g := CRules.raider(st, r)
	if g < 0 or not on(st) or not CState.grid_on(st) or CState.same_team(st, viewer, g):
		return g
	var v := _vis(st, viewer, vis)
	for a in st["armies"]:
		if int(a["r"]) == r and int(a["f"]) == g and CState.stance(a) == CData.ST_RAID and v[CState.cell(a)] != 0:
			return g
	return -1


## Event e (st["events"] / st["chronicle"]) may be told to viewer: it names
## a faction of viewer's team (keys f, from, to, a, b, o, by, att, def), or
## it is world news (no place: diplomacy, eliminations, victory, the teams),
## or its place (r, else x / y) was in viewer's sight at the event's turn
## or later (the memory's turn of that region; a cell: in sight now).
static func event_seen(st: Dictionary, viewer: int, e: Dictionary, vis: PackedByteArray = PackedByteArray()) -> bool:
	if not on(st):
		return true
	for k in ["f", "from", "to", "a", "b", "o", "by"]:
		var x = e.get(k)
		if (x is int) and CState.same_team(st, viewer, int(x)):
			return true
	for k in ["att", "def"]:
		var l = e.get(k)
		if l is Array:
			for x in l:
				if (x is int) and CState.same_team(st, viewer, int(x)):
					return true
	var r = e.get("r")
	if (r is int) and int(r) >= 0 and int(r) < CData.region_count():
		return known_turn(st, viewer, int(r), vis) >= int(e.get("turn", 0))
	if e.has("x") and e.has("y"):
		var c := CGrid.at(int(e["x"]), int(e["y"]))
		return c >= 0 and _vis(st, viewer, vis)[c] != 0
	return true


## The events of `list` viewer may be told (event_seen), in order.
static func events_for(st: Dictionary, viewer: int, list: Array, vis: PackedByteArray = PackedByteArray()) -> Array:
	var out: Array = []
	for e in list:
		if event_seen(st, viewer, e, vis):
			out.append(e)
	return out


# ------------------------------------------------------------ memory ---

static func _mem(st: Dictionary, f: int) -> Dictionary:
	if not on(st) or f < 0 or f >= (st["factions"] as Array).size():
		return {}
	var fs: Dictionary = st["factions"][f]
	return fs.get("mem", {})


## Write every faction's memory from its team's sight now (the end of
## resolve_turn, after a battle is applied, a new campaign, the 7 -> 8
## migration). A state of an older format is left alone.
static func update_memory(st: Dictionary) -> void:
	if not on(st):
		return
	CGrid.ensure()
	var turn := int(st.get("turn", 0))
	var nr := CData.region_count()
	var team_vis := {}  # team id -> sight (lookups only)
	for f in CState.nf():
		var t := CState.team(st, f)
		if not team_vis.has(t):
			team_vis[t] = compute(st, f)
		var vis: PackedByteArray = team_vis[t]
		var fs: Dictionary = st["factions"][f]
		var mem: Dictionary = fs.get("mem", {})
		if mem.is_empty() or (mem["own"] as Array).size() != nr:
			var own: Array = []
			var tn: Array = []
			for r in nr:
				own.append(-1)
				tn.append(-1)
			mem = {"own": own, "turn": tn, "mk": []}
			fs["mem"] = mem
		if not mem.has("lvl") or (mem["lvl"] as Array).size() != nr or (mem["wl"] as Array).size() != nr:
			var lv: Array = []
			var wl: Array = []
			for r in nr:
				lv.append(-1)
				wl.append(-1)
			mem["lvl"] = lv
			mem["wl"] = wl
		for r in nr:
			if _region_seen(vis, r):
				mem["own"][r] = CState.owner(st, r)
				mem["turn"][r] = turn
				mem["lvl"][r] = int(st["regions"][r]["level"])
				mem["wl"][r] = CState.walls(st, r)
		var mk: Array = []
		for m in mem["mk"]:
			var c := int(m["cell"])
			if c >= 0 and c < vis.size() and vis[c] == 0:
				mk.append(m)
		var fresh: Array = []
		var at := {}  # cell -> index in fresh (lookups only)
		if CState.grid_on(st):
			for a in st["armies"]:
				_seen(st, f, vis, fresh, at, int(a["f"]), CState.cell(a), 0, CState.unit_count(a), _army_name(st, int(a["id"])), turn)
		for fl in st.get("fleets", []):
			_seen(st, f, vis, fresh, at, int(fl["f"]), int(fl["y"]) * CGrid.width() + int(fl["x"]), 1,
				(fl["ships"] as Array).size(), "", turn)
		mk.append_array(fresh)
		if mk.size() > MAX_MARKERS:
			mk.sort_custom(func(x, y): return int(x["turn"]) > int(y["turn"]) \
				or (int(x["turn"]) == int(y["turn"]) and int(x["cell"]) < int(y["cell"])))
			mk.resize(MAX_MARKERS)
		mk.sort_custom(func(x, y): return int(x["cell"]) < int(y["cell"]))
		mem["mk"] = mk


static func _seen(st: Dictionary, f: int, vis: PackedByteArray, fresh: Array, at: Dictionary, g: int, c: int,
		kind: int, units: int, nm: String, turn: int) -> void:
	if c < 0 or c >= vis.size() or vis[c] == 0 or CState.same_team(st, f, g):
		return
	if at.has(c):
		var m: Dictionary = fresh[int(at[c])]
		m["units"] = int(m["units"]) + units
		return
	at[c] = fresh.size()
	fresh.append({"cell": c, "f": g, "kind": kind, "units": units, "turn": turn, "name": nm})


## The name a marker of army id carries: its hero's (the first character
## riding with it), else "".
static func _army_name(st: Dictionary, id: int) -> String:
	for ch in st.get("chars", []):
		if int(ch["army"]) == id:
			return str(ch.get("name", ""))
	return ""


# -------------------------------------------------------------- memo ---

## A cheap fingerprint of everything compute() reads (view memo only).
static func _signature(st: Dictionary, f: int) -> PackedInt64Array:
	var s := PackedInt64Array()
	s.resize(8)
	s[0] = f
	s[1] = int(st.get("version", 0))
	s[2] = int(st.get("turn", 0))
	var h := 0
	for r in (st["regions"] as Array).size():
		h = (h * 31 + int(st["regions"][r]["owner"]) + 2 + 64 * CState.walls(st, r)) & 0xFFFFFFFFFFFF
	s[3] = h
	h = 0
	for a in st.get("armies", []):
		h = (h * 31 + int(a.get("f", 0)) * 65536 + int(a.get("x", 0)) * 256 + int(a.get("y", 0)) + 7) & 0xFFFFFFFFFFFF
	s[4] = h
	h = 0
	for fl in st.get("fleets", []):
		h = (h * 31 + int(fl["f"]) * 65536 + int(fl["x"]) * 256 + int(fl["y"]) + 7) & 0xFFFFFFFFFFFF
	s[5] = h
	h = 0
	for ch in st.get("chars", []):
		h = (h * 31 + int(ch["f"]) * 65536 + int(ch["army"]) * 7 + int(ch["r"]) + 3) & 0xFFFFFFFFFFFF
	s[6] = h
	h = 0
	for t in st.get("teams", []):
		h = h * 31 + int(t) + 1
	s[7] = h & 0xFFFFFFFFFFFF
	return s
