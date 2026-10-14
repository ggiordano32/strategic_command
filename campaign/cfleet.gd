extends RefCounted
## Fleets on the campaign map (N1, West pack only: CData.ships_on(); docs/
## CAMPAIGN.md "Fleets (N1)"). A fleet is a piece on the sea cells of the nav
## grid with the overworld's movement: paths of cells, a reach a turn by its
## slowest ship and its heading against the map's wind (downwind farther,
## upwind shorter: integer step costs per direction). Armies board a fleet in
## port or on a coast cell beside it, sail with it and land on a coast cell
## (the landing ends their turn). Enemy fleets at war that come within
## FLEET_ZONE cells meet in a sea battle, auto-resolved at once by a
## deterministic formula (guns x hull x crew with the state's RNG; real-time
## sea battles are N3). Same discipline as the rest of campaign/: integers,
## the state's RNG, arrays in index order, no Nodes.
##
## State (only in a pack with ships; a Rome state never has these keys):
##   fleets [{id, f, x, y (its sea cell), ships [{t: ship key, h: hull %,
##     c: crew %}], carry [army dicts aboard, whole: they leave "armies"
##     while at sea], moved (0/1 this turn); optional dest_x, dest_y, tgt
##     (a stored voyage: the cell, or the enemy fleet it chases), land (1:
##     land the troops on arriving at dest, a coast cell), job (AI: the army
##     id it is fetching)}] sorted by id,
##   next_fleet, regions[r]["sq"] [ship keys] (ordered this turn, launched
##   at the end of it), stats["sea_battles"].
## Orders (crules.apply_order): ship {r, ship}, embark {army, fleet}, land
## {fleet, army (-1 all), x, y}, fmove {fleet, x, y, tgt?, persist?} (a
## land cell: sail beside it and land everything aboard on arriving),
## fmerge {fleet, into}, fcancel {fleet}, scuttle {fleet, ship}.
## Hooks for N2 (trade, blockades, the flota, pirates) are the docks and
## harbours per region, the pirates' capture share and the sea battle event.

const CData := preload("res://campaign/cdata.gd")
const CState := preload("res://campaign/cstate.gd")
const CGrid := preload("res://campaign/cgrid.gd")
const UT := preload("res://sim/unit_types.gd")

const INF := 1 << 30
## A fleet's zone (cells, the circle of CGrid.within): an enemy fleet at war
## stepping into it fights it; paths avoid it unless it is the target.
const FLEET_ZONE := 2
## A harbour (the coast cell ships are built and boarded at) is at most this
## far (Chebyshev) from the settlement.
const HARBOUR_MAX := 4
## Turns a voyage is searched ahead (players' stored voyages).
const MAX_TURNS := 12
const MAX_NODES := 8000
## In port (within PORT_CELLS of an own harbour): repairs a turn (hull and
## crew %), + REPAIR_YARD a Shipyard level; at sea crew is lost to scurvy.
const PORT_CELLS := 2
const REPAIR := 15
const REPAIR_YARD := 10
const SCURVY := 2
const SCURVY_FLOOR := 40
## Sea battle formula (auto-resolve; fitted to the real-time battles in N3).
const ROLL_MIN := 85            # each side's roll: ROLL_MIN .. ROLL_MIN + ROLL_SPAN %
const ROLL_SPAN := 31
const LOSS_BASE := 20           # a losing ship is lost: LOSS_BASE + 2 x (winner's share - 50) %
const LOSS_MAX := 95
const CAPTURE_PCT := 25         # a lost ship is taken (not sunk) this often ...
const PIRATE_CAPTURE_PCT := 60  # ... by pirates (PIRATES) this often
const PIRATES: Array[String] = ["brethren"]
const TAKEN_PCT := 35           # a prize joins its captor at this hull and crew
const PORT_DEF_PCT := 110       # defenders in their own port: x this % ...
const PORT_WALL_PCT := 15       # ... + this % per walls level (shore batteries)
const RETREAT_R := 5

static var _sea := PackedByteArray()     # 1: a sea cell of the open sea (the largest water body)
static var _cd := PackedByteArray()      # Chebyshev distance to land, capped at 3 (0 land)
static var _snb := PackedInt32Array()    # n * 8: sea neighbour or -1
static var _harb: Array[int] = []        # per region: the harbour (coast land cell) or -1
static var _dock: Array[int] = []        # per region: the dock (sea cell beside the harbour) or -1
static var _beach: Array[int] = []       # per region: the coast cell nearest the settlement (landings) or -1
static var _cost_w: Array[int] = []      # step cost per direction with the wind
static var _ccomp := PackedInt32Array()  # coastal water (within COASTAL_CELLS of land) component per sea cell, -1 other
static var _mlog: Array = []


static func _rules() -> GDScript:
	return load("res://campaign/crules.gd")


## The pack changed (CData.use_pack_script).
static func pack_reset() -> void:
	_sea = PackedByteArray()
	_cd = PackedByteArray()
	_snb = PackedInt32Array()
	_harb = []
	_dock = []
	_beach = []
	_cost_w = []
	_ccomp = PackedInt32Array()


# ------------------------------------------------------------ sea tables ---

static func ensure() -> void:
	if not _sea.is_empty() or not CData.ships_on():
		return
	var n := CGrid.count()
	var w := CGrid.width()
	var raw := PackedByteArray()
	raw.resize(n)
	for i in n:
		raw[i] = 1 if CGrid.region(i) == -1 else 0
	# Distance to land (Chebyshev, capped at 3).
	_cd.resize(n)
	for i in n:
		if raw[i] == 0:
			_cd[i] = 0
			continue
		var x := i % w
		var y := i / w
		var d := 3
		for r in range(1, 3):
			var hit := false
			for dy in range(-r, r + 1):
				for dx in range(-r, r + 1):
					if maxi(absi(dx), absi(dy)) != r:
						continue
					var j := CGrid.at(x + dx, y + dy)
					if j >= 0 and raw[j] == 0:
						hit = true
			if hit:
				d = r
				break
		_cd[i] = d
	# Sea steps (8-connected; a diagonal needs one of its orthogonals at sea).
	var nb := PackedInt32Array()
	nb.resize(n * 8)
	nb.fill(-1)
	for i in n:
		if raw[i] == 0:
			continue
		var x := i % w
		var y := i / w
		for k in 8:
			var j := CGrid.at(x + CGrid.DX[k], y + CGrid.DY[k])
			if j < 0 or raw[j] == 0:
				continue
			if k % 2 == 1:
				var oa := CGrid.at(x + CGrid.DX[k], y)
				var ob := CGrid.at(x, y + CGrid.DY[k])
				if not ((oa >= 0 and raw[oa] != 0) or (ob >= 0 and raw[ob] != 0)):
					continue
			nb[i * 8 + k] = j
	# The open sea: the largest connected water (lakes and lagoons are not).
	var comp := PackedInt32Array()
	comp.resize(n)
	comp.fill(-1)
	var best := -1
	var best_n := 0
	var nc := 0
	for i in n:
		if raw[i] == 0 or comp[i] >= 0:
			continue
		var stack: Array[int] = [i]
		comp[i] = nc
		var cnt := 0
		while not stack.is_empty():
			var u: int = stack.pop_back()
			cnt += 1
			for k in 8:
				var v := nb[u * 8 + k]
				if v >= 0 and comp[v] < 0:
					comp[v] = nc
					stack.append(v)
		if cnt > best_n:
			best_n = cnt
			best = nc
		nc += 1
	_sea.resize(n)
	for i in n:
		_sea[i] = 1 if raw[i] != 0 and comp[i] == best else 0
	for i in n * 8:
		if nb[i] >= 0 and _sea[nb[i]] == 0:
			nb[i] = -1
	_snb = nb
	# Harbours, docks and beaches.
	_harb = []
	_dock = []
	_beach = []
	for r in CData.region_count():
		var s := CGrid.site(r)
		var hb := -1
		var hd := INF
		for c in CGrid.cells_of(r):
			if _sea_next(c) < 0:
				continue
			var dd := CGrid.d2(c, s) + (1 << 20 if c == s else 0)  # (the settlement's own cell last)
			if dd < hd:
				hd = dd
				hb = c
		_beach.append(hb)
		var port := CGrid.port(r)
		if port >= 0 and _sea_next(port) >= 0:
			hb = port
		if hb >= 0 and CGrid.cheb(hb, s) > HARBOUR_MAX:
			hb = -1
		_harb.append(hb)
		var dk := -1
		if hb >= 0:
			var bd := INF
			for k in 8:
				var j := CGrid.at(CGrid.cx(hb) + CGrid.DX[k], CGrid.cy(hb) + CGrid.DY[k])
				if j >= 0 and _sea[j] != 0 and CGrid.d2(j, s) < bd:
					bd = CGrid.d2(j, s)
					dk = j
		_dock.append(dk)
	# Step costs with the wind (per direction N, NE ... NW).
	var to_deg := (int(CData.ship_const("WIND_FROM_DEG", 90)) + 180) % 360
	var down := ((to_deg + 22) / 45) % 8
	var pct: Array = CData.ship_const("WIND_PCT", [100, 100, 100, 100, 100])
	# Coastal water's components (where canoes can go from where).
	var lim := int(CData.ship_const("COASTAL_CELLS", 2))
	_ccomp.resize(n)
	_ccomp.fill(-1)
	var ncc := 0
	for i in n:
		if _sea[i] == 0 or _cd[i] > lim or _ccomp[i] >= 0:
			continue
		var stack2: Array[int] = [i]
		_ccomp[i] = ncc
		while not stack2.is_empty():
			var u: int = stack2.pop_back()
			for k in 8:
				var v := nb[u * 8 + k]
				if v >= 0 and _cd[v] <= lim and _ccomp[v] < 0:
					_ccomp[v] = ncc
					stack2.append(v)
		ncc += 1
	_cost_w = []
	for k in 8:
		var s2 := absi(k - down)
		s2 = mini(s2, 8 - s2)
		var base := 10 if k % 2 == 0 else 14
		_cost_w.append(base * 100 / int(pct[s2]))


## A sea cell of the open sea next to land cell c (-1 none; neighbour order).
static func _sea_next(c: int) -> int:
	for k in 8:
		var j := CGrid.at(CGrid.cx(c) + CGrid.DX[k], CGrid.cy(c) + CGrid.DY[k])
		if j >= 0 and _sea_raw(j):
			return j
	return -1


static func _sea_raw(c: int) -> bool:
	if not _sea.is_empty():
		return _sea[c] != 0
	return CGrid.region(c) == -1


## Cell c is open sea (where fleets sail).
static func is_sea(c: int) -> bool:
	ensure()
	return c >= 0 and c < _sea.size() and _sea[c] != 0


## Chebyshev distance from sea cell c to land (capped at 3; 0 on land).
static func coast_dist(c: int) -> int:
	ensure()
	return _cd[c] if c >= 0 and c < _cd.size() else 0


## Region r's harbour (the coast cell nearest its settlement, within
## HARBOUR_MAX of it), -1 inland.
static func harbour(r: int) -> int:
	ensure()
	return _harb[r] if r >= 0 and r < _harb.size() else -1


## The sea cell where region r's ships are launched and wait (-1 none).
static func dock(r: int) -> int:
	ensure()
	return _dock[r] if r >= 0 and r < _dock.size() else -1


## The coast cell of region r nearest its settlement, any distance (where a
## landing aims for that region), -1 landlocked.
static func beach(r: int) -> int:
	ensure()
	return _beach[r] if r >= 0 and r < _beach.size() else -1


## A coastal fleet at sea cell a can reach cell b (sea, or land: a sea cell
## beside it) keeping to coastal water.
static func coastal_link(a: int, b: int) -> bool:
	ensure()
	if a < 0 or b < 0 or _ccomp[a] < 0:
		return false
	if is_sea(b):
		return _ccomp[b] == _ccomp[a]
	for k in 8:
		var j := CGrid.at(CGrid.cx(b) + CGrid.DX[k], CGrid.cy(b) + CGrid.DY[k])
		if j >= 0 and is_sea(j) and _ccomp[j] == _ccomp[a]:
			return true
	return false


## Step cost of direction k (0 N ... 7 NW) for a fleet with sails (wind) or rowed.
static func step_cost(k: int, wind: bool) -> int:
	ensure()
	if not wind:
		return 10 if k % 2 == 0 else 14
	return _cost_w[k]


## The wind's pace % for direction k (WIND_PCT by the angle to the wind).
static func wind_pct(k: int) -> int:
	return (10 if k % 2 == 0 else 14) * 100 / maxi(step_cost(k, true), 1)


# ----------------------------------------------------------- fleet facts ---

static func on(st: Dictionary) -> bool:
	return st.has("fleets")


static func fleets(st: Dictionary) -> Array:
	return st.get("fleets", [])


static func fleet(st: Dictionary, id: int) -> Dictionary:
	for fl in fleets(st):
		if int(fl["id"]) == id:
			return fl
	return {}


static func fleets_of(st: Dictionary, f: int) -> Array:
	var out: Array = []
	for fl in fleets(st):
		if int(fl["f"]) == f:
			out.append(fl)
	return out


static func cell(fl: Dictionary) -> int:
	return int(fl["y"]) * CGrid.width() + int(fl["x"])


static func place(fl: Dictionary, c: int) -> void:
	fl["x"] = CGrid.cx(c)
	fl["y"] = CGrid.cy(c)


## Movement points a turn (the slowest ship's speed).
static func speed(fl: Dictionary) -> int:
	var sp := INF
	for s in fl["ships"]:
		sp = mini(sp, int(CData.ship_row(str(s["t"])).get("speed", 0)))
	return 0 if sp >= INF else sp


## The fleet keeps to the coast (a coastal ship in it).
static func coastal(fl: Dictionary) -> bool:
	for s in fl["ships"]:
		if int(CData.ship_row(str(s["t"])).get("coastal", 0)) != 0:
			return true
	return false


## The fleet sails (a ship with sails in it: the wind sets its pace).
static func sails(fl: Dictionary) -> bool:
	for s in fl["ships"]:
		if int(CData.ship_row(str(s["t"])).get("oars", 0)) == 0:
			return true
	return false


## Army units it carries at most.
static func capacity(fl: Dictionary) -> int:
	var c := 0
	for s in fl["ships"]:
		c += int(CData.ship_row(str(s["t"])).get("cap", 0))
	return c


## Army units aboard.
static func carried_units(fl: Dictionary) -> int:
	var n := 0
	for a in fl["carry"]:
		n += CState.unit_count(a)
	return n


static func ship_power(s: Dictionary) -> int:
	var row := CData.ship_row(str(s["t"]))
	if row.is_empty():
		return 0
	var base := int(row["guns"]) * 10 + int(row["hull"]) + int(row["crew"]) / 5
	return base * (int(s["h"]) + int(s["c"])) / 200


## Fighting power of a fleet (guns x hull x crew; the formula's and the AI's).
static func power(fl: Dictionary) -> int:
	var p := 0
	for s in fl["ships"]:
		p += ship_power(s)
	return p


static func upkeep(st: Dictionary, f: int) -> int:
	var u := 0
	for fl in fleets(st):
		if int(fl["f"]) != f:
			continue
		for s in fl["ships"]:
			u += int(CData.ship_row(str(s["t"])).get("upkeep", 0))
		for a in fl["carry"]:
			for unit in a["units"]:
				u += CState.upkeep_of(CState.unit_type(unit))
	return u


## The fleet carrying army id ({} none).
static func carrier(st: Dictionary, id: int) -> Dictionary:
	for fl in fleets(st):
		for a in fl["carry"]:
			if int(a["id"]) == id:
				return fl
	return {}


## Region whose harbour the fleet lies in (within PORT_CELLS), owned by f
## (or friendly to it when `friendly`), -1 none (the lowest index).
static func port_of(st: Dictionary, fl: Dictionary, f: int, friendly: bool = false) -> int:
	var c := cell(fl)
	for r in CData.region_count():
		var hb := harbour(r)
		if hb < 0 or CGrid.cheb(c, hb) > PORT_CELLS:
			continue
		var o := CState.owner(st, r)
		if o == f or (friendly and CState.friendly(st, f, o)):
			return r
	return -1


## Ship keys faction f may build in region r (by its Shipyard), [] none.
static func buildable(st: Dictionary, f: int, r: int) -> Array:
	var out: Array = []
	if f < 0 or harbour(r) < 0 or dock(r) < 0:
		return out
	var yard := CState.building(st, r, CData.SHIPYARD)
	var fk := str(CData.FACTIONS[f]["key"])
	for row in CData.ship_rows():
		if (row["factions"] as Array).has(fk) and int(row["yard"]) <= yard:
			out.append(str(row["key"]))
	return out


## "" if faction f may order ship `key` in region r now, else why not.
static func ship_check(st: Dictionary, f: int, r: int, key: String) -> String:
	if not on(st):
		return "no ships here"
	if r < 0 or r >= CData.region_count():
		return "bad order"
	var row := CData.ship_row(key)
	if row.is_empty():
		return "no such ship"
	if CState.owner(st, r) != f:
		return "not your region"
	if harbour(r) < 0 or dock(r) < 0:
		return "not a port"
	if not (row["factions"] as Array).has(str(CData.FACTIONS[f]["key"])):
		return "your people do not build these"
	if CState.building(st, r, CData.SHIPYARD) < int(row["yard"]):
		return "needs Shipyard %d" % int(row["yard"])
	if not CState.siege_at(st, r).is_empty():
		return "besieged"
	if not CState.battle_at(st, r).is_empty():
		return "battle pending there"
	if not (st["regions"][r].get("sq", []) as Array).is_empty():
		return "already launching a ship"
	if int(row["cost"]) > int(st["factions"][f]["treasury"]):
		return "not enough money"
	return ""


# ----------------------------------------------------------- new campaign ---

## A new campaign of a pack with ships: the starting shipyards and fleets.
static func init(st: Dictionary) -> void:
	st["fleets"] = []
	st["next_fleet"] = 1
	for y in CData.ship_const("START_YARDS", []):
		var r := CData.region_index(str(y[0]))
		if r < 0 or harbour(r) < 0:
			continue
		var rs: Dictionary = st["regions"][r]
		var done := false
		for s in rs["slots"]:
			if int(s[0]) == CData.SHIPYARD:
				s[1] = maxi(int(s[1]), int(y[1]))
				done = true
		if not done:
			(rs["slots"] as Array).append([CData.SHIPYARD, int(y[1])])
	for sf in CData.ship_const("START_FLEETS", []):
		var f := CData.faction_index(str(sf[0]))
		var r := CData.region_index(str(sf[1]))
		if f < 0 or r < 0 or dock(r) < 0 or CState.owner(st, r) != f:
			continue
		var ships: Array = []
		for k in sf[2]:
			if CData.ship_index(str(k)) >= 0:
				ships.append({"t": str(k), "h": 100, "c": 100})
		if not ships.is_empty():
			_new_fleet(st, f, dock(r), ships)


static func _new_fleet(st: Dictionary, f: int, c: int, ships: Array) -> Dictionary:
	var fl := {"id": int(st["next_fleet"]), "f": f, "x": CGrid.cx(c), "y": CGrid.cy(c), "ships": ships,
		"carry": [], "moved": 0}
	st["next_fleet"] = int(st["next_fleet"]) + 1
	var arr: Array = st["fleets"]
	var i := 0
	while i < arr.size() and int(arr[i]["id"]) < int(fl["id"]):
		i += 1
	arr.insert(i, fl)
	return fl


# ----------------------------------------------------------------- orders ---

## crules.apply_order's fleet orders. Returns "" or why not.
static func apply_order(st: Dictionary, f: int, o: Dictionary) -> String:
	if not on(st):
		return "no ships here"
	match str(o.get("t", "")):
		"ship":
			return _order_ship(st, f, int(o.get("r", -1)), str(o.get("ship", "")))
		"embark":
			return _embark(st, f, int(o.get("army", -1)), int(o.get("fleet", -1)))
		"land":
			return _land_order(st, f, int(o.get("fleet", -1)), int(o.get("army", -1)),
				CGrid.at(int(o.get("x", -1)), int(o.get("y", -1))))
		"fmove":
			return move_check(st, f, int(o.get("fleet", -1)), CGrid.at(int(o.get("x", -1)), int(o.get("y", -1))),
				int(o.get("tgt", -1)))
		"fmerge":
			return _fmerge(st, f, int(o.get("fleet", -1)), int(o.get("into", -1)))
		"fcancel":
			var fl := fleet(st, int(o.get("fleet", -1)))
			if fl.is_empty() or int(fl["f"]) != f:
				return "no such fleet"
			_drop_voyage(fl)
			return ""
		"scuttle":
			return _scuttle(st, f, int(o.get("fleet", -1)), int(o.get("ship", -1)))
	return "unknown order"


static func _order_ship(st: Dictionary, f: int, r: int, key: String) -> String:
	var why := ship_check(st, f, r, key)
	if why != "":
		return why
	st["factions"][f]["treasury"] = int(st["factions"][f]["treasury"]) - int(CData.ship_row(key)["cost"])
	st["regions"][r]["sq"] = [key]
	return ""


## "" if army id of faction f may board fleet fid now, else why not.
static func embark_check(st: Dictionary, f: int, id: int, fid: int) -> String:
	var a := CState.army(st, id)
	if a.is_empty() or int(a["f"]) != f:
		return "no such army"
	var fl := fleet(st, fid)
	if fl.is_empty() or int(fl["f"]) != f:
		return "no such fleet"
	if int(a["busy"]) != 0 or _rules().in_battle(st, id):
		return "in a battle"
	if _rules().siege_role(st, a) != 0:
		return "in a siege"
	if not near_fleet(a, fl):
		return "not beside the fleet"
	if carried_units(fl) + CState.unit_count(a) > capacity(fl):
		return "not enough room aboard (%d of %d)" % [carried_units(fl), capacity(fl)]
	return ""


## Army a stands where it can board fleet fl: next to it (Chebyshev 1), or
## in a settlement whose harbour the fleet lies beside.
static func near_fleet(a: Dictionary, fl: Dictionary) -> bool:
	var ac := CState.cell(a)
	var fc := cell(fl)
	if CGrid.cheb(ac, fc) <= 1:
		return true
	var r := CGrid.site_region(ac)
	return r >= 0 and harbour(r) >= 0 and CGrid.cheb(harbour(r), fc) <= 1


static func _embark(st: Dictionary, f: int, id: int, fid: int) -> String:
	var why := embark_check(st, f, id, fid)
	if why != "":
		return why
	var fl := fleet(st, fid)
	var i := CState.army_index(st, id)
	var a: Dictionary = st["armies"][i]
	(st["armies"] as Array).remove_at(i)
	_rules()._drop_march(a)
	a["stance"] = CData.ST_DEFAULT
	(fl["carry"] as Array).append(a)
	_rules().event(st, {"k": "embarked", "f": f, "army": id, "fleet": fid, "r": int(a["r"])})
	return ""


## Land cell c is somewhere faction f may land: passable, a land it may
## enter, not a hostile settlement, no enemy army on it.
static func land_ok(st: Dictionary, f: int, c: int) -> bool:
	if c < 0 or not CGrid.passable(c):
		return false
	var r := CGrid.region(c)
	if _rules().can_enter(st, f, r) != "":
		return false
	var sr := CGrid.site_region(c)
	if sr >= 0 and not CState.friendly(st, f, CState.owner(st, sr)):
		return false
	for e in st["armies"]:
		if CState.cell(e) == c and not CState.friendly(st, f, int(e["f"])):
			return false
	return true


## Where fleet fl (at its cell) lands troops aiming for cell want: want if
## it is beside the fleet and fit, else the fit land cell beside the fleet
## nearest it (ties by cell index), -1 none.
static func landing_cell(st: Dictionary, f: int, fl: Dictionary, want: int) -> int:
	var fc := cell(fl)
	if want >= 0 and CGrid.cheb(want, fc) <= 1 and land_ok(st, f, want):
		return want
	var best := -1
	var bd := INF
	for k in 8:
		var j := CGrid.at(CGrid.cx(fc) + CGrid.DX[k], CGrid.cy(fc) + CGrid.DY[k])
		if j < 0 or not land_ok(st, f, j):
			continue
		var d := CGrid.d2(j, want) if want >= 0 else 0
		if d < bd or (d == bd and j < best):
			bd = d
			best = j
	return best


static func _land_order(st: Dictionary, f: int, fid: int, id: int, c: int) -> String:
	var fl := fleet(st, fid)
	if fl.is_empty() or int(fl["f"]) != f:
		return "no such fleet"
	if (fl["carry"] as Array).is_empty():
		return "nobody aboard"
	if c < 0 or CGrid.cheb(c, cell(fl)) > 1:
		return "not beside the fleet"
	if not land_ok(st, f, c):
		return "cannot land there"
	if id >= 0 and carrier(st, id) != fl:
		return "not aboard"
	land(st, fl, c, id)
	return ""


## Land the troops of fleet fl (army id, or all with -1) on cell c (fit:
## land_ok). Their move ends for this turn.
static func land(st: Dictionary, fl: Dictionary, c: int, id: int = -1) -> void:
	var keep: Array = []
	for a in fl["carry"]:
		if id >= 0 and int(a["id"]) != id:
			keep.append(a)
			continue
		CState.place(a, c)
		a["moved"] = 1
		a["mp"] = 0
		a["busy"] = 0
		a["idle"] = 0
		_rules()._drop_march(a)
		a["stance"] = CData.ST_DEFAULT
		_rules()._insert_army(st, a)
		a["mp"] = 0
		_rules().event(st, {"k": "landed", "f": int(a["f"]), "army": int(a["id"]), "fleet": int(fl["id"]),
			"r": CGrid.region(c), "x": CGrid.cx(c), "y": CGrid.cy(c)})
	fl["carry"] = keep


static func _fmerge(st: Dictionary, f: int, fid: int, into: int) -> String:
	var a := fleet(st, fid)
	var b := fleet(st, into)
	if a.is_empty() or b.is_empty() or int(a["f"]) != f or int(b["f"]) != f or fid == into:
		return "no such fleet"
	if CGrid.cheb(cell(a), cell(b)) > 1:
		return "too far apart"
	(b["ships"] as Array).append_array(a["ships"])
	(b["carry"] as Array).append_array(a["carry"])
	b["moved"] = maxi(int(a["moved"]), int(b["moved"]))
	(st["fleets"] as Array).erase(a)
	return ""


static func _scuttle(st: Dictionary, f: int, fid: int, k: int) -> String:
	var fl := fleet(st, fid)
	if fl.is_empty() or int(fl["f"]) != f:
		return "no such fleet"
	var ships: Array = fl["ships"]
	if k < 0 or k >= ships.size():
		return "bad order"
	if ships.size() == 1 and not (fl["carry"] as Array).is_empty():
		return "troops aboard"
	ships.remove_at(k)
	_sink_extra(st, fl, [])
	if ships.is_empty():
		(st["fleets"] as Array).erase(fl)
	return ""


# --------------------------------------------------------------- voyages ---

## Cells fleet fl of faction f may not enter: the zones of enemy fleets at
## war (but the target's: tgt), and for a coastal fleet the open water.
static func block_mask(st: Dictionary, f: int, tgt: int = -1) -> PackedByteArray:
	ensure()
	var m := PackedByteArray()
	m.resize(CGrid.count())
	m.fill(0)
	for e in fleets(st):
		if int(e["id"]) == tgt or not CState.at_war(st, f, int(e["f"])):
			continue
		for c in CGrid.disc(cell(e), FLEET_ZONE):
			m[c] = 1
	return m


## A path of fleet fl from where it is to goal (adjacent: stop beside it, a
## landing or an enemy fleet) with the fleet's points: {path, t, m} as
## CGrid.find_path, or {} none.
static func find_path(fl: Dictionary, goal: int, block: PackedByteArray, adjacent: bool,
		max_turns: int = MAX_TURNS, max_nodes: int = MAX_NODES) -> Dictionary:
	ensure()
	var start := cell(fl)
	var full := speed(fl)
	if start < 0 or goal < 0 or full <= 0:
		return {}
	if (adjacent and CGrid.cheb(start, goal) <= 1) or (not adjacent and start == goal):
		return {"path": [], "t": [], "m": []}
	var wind := sails(fl)
	var coast := coastal(fl)
	var lim := int(CData.ship_const("COASTAL_CELLS", 2))
	var n := CGrid.count()
	var w := CGrid.width()
	var g := PackedInt32Array()
	g.resize(n)
	g.fill(INF)
	var prev := PackedInt32Array()
	prev.resize(n)
	prev.fill(-1)
	var has_block := block.size() == n
	var gx := goal % w
	var gy := goal / w
	var m0 := full if int(fl.get("moved", 0)) == 0 else 0
	g[start] = full - m0
	var cmin := 10
	if wind:
		for k in 8:
			if k % 2 == 0:
				cmin = mini(cmin, _cost_w[k])
	var heap: Array[int] = []
	heap.append((g[start] + _hs(start, gx, gy, w, cmin)) * 65536 + start)
	var found := -1
	var nodes := 0
	var cap := max_turns * full + full
	while not heap.is_empty():
		var top: int = CGrid._pop(heap)
		var u := top & 65535
		var gu := g[u]
		if top >> 16 != gu + _hs(u, gx, gy, w, cmin):
			continue
		if adjacent:
			if absi(u % w - gx) <= 1 and absi(u / w - gy) <= 1:
				found = u
				break
		elif u == goal:
			found = u
			break
		nodes += 1
		if nodes > max_nodes or gu > cap:
			break
		var t := gu / full
		var left := full - (gu - t * full)
		if gu > 0 and gu % full == 0:
			t = gu / full - 1
			left = 0
		for k in 8:
			var v := _snb[u * 8 + k]
			if v < 0 or (has_block and block[v] != 0) or (coast and _cd[v] > lim):
				continue
			var c := _cost_w[k] if wind else (10 if k % 2 == 0 else 14)
			var ng := gu + c if left >= c else (t + 1) * full + c
			if ng < g[v]:
				g[v] = ng
				prev[v] = u
				CGrid._push(heap, (ng + _hs(v, gx, gy, w, cmin)) * 65536 + v)
	if found < 0:
		return {}
	var path: Array = []
	var c2 := found
	while c2 != start:
		path.push_front(c2)
		c2 = prev[c2]
	var ts: Array = []
	var ms: Array = []
	for c3 in path:
		var gv := g[c3]
		var tt := gv / full
		var lf := full - (gv - tt * full)
		if gv > 0 and gv % full == 0:
			tt -= 1
			lf = 0
		ts.append(tt)
		ms.append(lf)
	return {"path": path, "t": ts, "m": ms}


static func _hs(c: int, gx: int, gy: int, w: int, cmin: int) -> int:
	var dx := absi(c % w - gx)
	var dy := absi(c / w - gy)
	return (cmin * maxi(dx, dy) + cmin * 4 / 10 * mini(dx, dy)) * 3 / 2


## Sea cells fleet fl reaches: per cell the turn (0 this turn ... max_t), -1
## never (Dijkstra on the find_path costs; the view's reach preview).
static func reach(st: Dictionary, fl: Dictionary, max_t: int = 0) -> PackedInt32Array:
	ensure()
	var n := CGrid.count()
	var out := PackedInt32Array()
	out.resize(n)
	out.fill(-1)
	var full := speed(fl)
	if full <= 0 or int(fl.get("moved", 0)) != 0:
		return out
	var block := block_mask(st, int(fl["f"]))
	var wind := sails(fl)
	var coast := coastal(fl)
	var lim := int(CData.ship_const("COASTAL_CELLS", 2))
	var g := PackedInt32Array()
	g.resize(n)
	g.fill(INF)
	var start := cell(fl)
	g[start] = 0
	var heap: Array[int] = [start]
	var cap := (max_t + 1) * full
	while not heap.is_empty():
		var top: int = CGrid._pop(heap)
		var u := top & 65535
		var gu := g[u]
		if top >> 16 != gu:
			continue
		var t := gu / full
		var left := full - (gu - t * full)
		if gu > 0 and gu % full == 0:
			t -= 1
			left = 0
		out[u] = t
		for k in 8:
			var v := _snb[u * 8 + k]
			if v < 0 or block[v] != 0 or (coast and _cd[v] > lim):
				continue
			var c := _cost_w[k] if wind else (10 if k % 2 == 0 else 14)
			var ng := gu + c if left >= c else (t + 1) * full + c
			if ng <= cap and ng < g[v]:
				g[v] = ng
				CGrid._push(heap, ng * 65536 + v)
	return out


## The enemy fleet (at war with f) whose zone holds cell c, nearest first
## (-1 none).
static func zone_owner(st: Dictionary, f: int, c: int) -> int:
	var best := -1
	var bd := INF
	for e in fleets(st):
		if not CState.at_war(st, f, int(e["f"])):
			continue
		if CGrid.within(cell(e), c, FLEET_ZONE) and CGrid.d2(cell(e), c) < bd:
			bd = CGrid.d2(cell(e), c)
			best = int(e["id"])
	return best


## Plan of a voyage of fleet fid of faction f to cell dest (a sea cell, or a
## coast cell to land on) or after enemy fleet tgt: {path, t, m, goal, land,
## tgt} or {why}. A destination in an enemy fleet's zone is an attack on it.
static func plan(st: Dictionary, f: int, fid: int, dest: int, tgt: int = -1, max_turns: int = MAX_TURNS) -> Dictionary:
	ensure()
	var fl := fleet(st, fid)
	if fl.is_empty() or int(fl["f"]) != f:
		return {"why": "no such fleet"}
	if int(fl.get("moved", 0)) != 0:
		return {"why": "already sailed this turn"}
	if fl["ships"].is_empty():
		return {"why": "no ships"}
	var landing := false
	if tgt >= 0:
		var tf := fleet(st, tgt)
		if tf.is_empty() or not CState.at_war(st, f, int(tf["f"])):
			return {"why": "not an enemy fleet"}
		dest = cell(tf)
	elif dest < 0:
		return {"why": "bad order"}
	elif not is_sea(dest):
		if not CGrid.passable(dest):
			return {"why": "not on the sea"}
		landing = true
	else:
		var zo := zone_owner(st, f, dest)
		if zo >= 0:
			tgt = zo
			dest = cell(fleet(st, zo))
	if landing:
		if (fl["carry"] as Array).is_empty():
			return {"why": "nobody aboard to land"}
		if _sea_next(dest) < 0:
			return {"why": "not on the coast"}
		var r := CGrid.region(dest)
		if _rules().can_enter(st, f, r) != "":
			return {"why": _rules().can_enter(st, f, r)}
	if coastal(fl) and not coastal_link(cell(fl), dest):
		return {"why": "too far from the coast for canoes"}
	var p := find_path(fl, dest, block_mask(st, f, tgt), landing or tgt >= 0, max_turns)
	if p.is_empty():
		return {"why": "no way there by sea"}
	p["goal"] = dest
	p["land"] = 1 if landing else 0
	p["tgt"] = tgt
	return p


static func move_check(st: Dictionary, f: int, fid: int, dest: int, tgt: int = -1) -> String:
	var p := plan(st, f, fid, dest, tgt)
	return str(p.get("why", ""))


static func _drop_voyage(fl: Dictionary) -> void:
	fl.erase("dest_x")
	fl.erase("dest_y")
	fl.erase("tgt")
	fl.erase("land")


## Fleet fl's stored voyage as [cell, tgt] ([-1, -1] none).
static func voyage(fl: Dictionary) -> Array:
	var c := CGrid.at(int(fl.get("dest_x", -1)), int(fl.get("dest_y", -1))) if fl.has("dest_x") else -1
	return [c, int(fl.get("tgt", -1))]


## Run a phase's voyages: moves [[fleet id, dest cell, faction, persist,
## tgt], ...]. Paths are planned first, then every fleet takes one step a
## round (by id); a step into an enemy fleet's zone is a sea battle at once
## (every fleet in it stops). A voyage that ends on a coast cell lands the
## troops. persist: a voyage not finished this turn is stored and goes on.
static func execute_moves(st: Dictionary, moves: Array) -> void:
	if not on(st) or moves.is_empty():
		return
	ensure()
	var list := moves.duplicate()
	list.sort_custom(func(a, b): return int(a[0]) < int(b[0]))
	var plans: Array = []
	var seen := {}
	for m in list:
		var fid := int(m[0])
		if seen.has(fid):
			continue
		seen[fid] = 1
		var fl := fleet(st, fid)
		if fl.is_empty() or int(fl["f"]) != int(m[2]):
			continue
		var p := plan(st, int(m[2]), fid, int(m[1]), int(m[4]) if m.size() > 4 else -1)
		if p.has("why"):
			_drop_voyage(fl)
			_rules().event(st, {"k": "fmove_failed", "f": int(m[2]), "fleet": fid, "why": str(p["why"])})
			continue
		var steps: Array = []
		var path: Array = p["path"]
		for i in path.size():
			if int(p["t"][i]) == 0:
				steps.append(int(path[i]))
		var done := steps.size() == path.size()
		if done or int(m[3]) == 0:
			_drop_voyage(fl)
		else:
			var dc := int(m[1]) if int(p["tgt"]) < 0 else int(p["goal"])
			fl["dest_x"] = CGrid.cx(dc)
			fl["dest_y"] = CGrid.cy(dc)
			if int(p["tgt"]) >= 0:
				fl["tgt"] = int(p["tgt"])
			if int(p["land"]) != 0:
				fl["land"] = 1
		fl["moved"] = 1
		plans.append({"id": fid, "steps": steps, "done": done, "goal": int(p["goal"]), "land": int(p["land"]),
			"stop": false})
	_mlog = []
	var rounds := 0
	for p in plans:
		rounds = maxi(rounds, (p["steps"] as Array).size())
	for i in rounds:
		for p in plans:
			if bool(p["stop"]) or i >= (p["steps"] as Array).size():
				continue
			var fl := fleet(st, int(p["id"]))
			if fl.is_empty():
				p["stop"] = true
				continue
			var c := int(p["steps"][i])
			place(fl, c)
			_mlog.append([int(fl["id"]), c])
			var foes: Array = []
			for e in fleets(st):
				if CState.at_war(st, int(fl["f"]), int(e["f"])) and CGrid.within(c, cell(e), FLEET_ZONE):
					foes.append(e)
			if foes.is_empty():
				continue
			var involved := sea_battle(st, fl, foes, c)
			for q in plans:
				if involved.has(int(q["id"])):
					q["stop"] = true
			p["stop"] = true
	for p in plans:
		if bool(p["stop"]) or not bool(p["done"]) or int(p["land"]) == 0:
			continue
		var fl := fleet(st, int(p["id"]))
		if fl.is_empty() or (fl["carry"] as Array).is_empty():
			continue
		var lc := landing_cell(st, int(fl["f"]), fl, int(p["goal"]))
		if lc < 0:
			_rules().event(st, {"k": "fmove_failed", "f": int(fl["f"]), "fleet": int(fl["id"]), "why": "nowhere to land"})
			continue
		land(st, fl, lc)
	if not _mlog.is_empty():
		_rules().event(st, {"k": "fmoves", "steps": _mlog.duplicate()})


# ------------------------------------------------------------ sea battles ---

## A sea battle at cell c: fleet `mover` stepped into the zone of `foes`
## (fleets at war with it). Every fleet of either side within FLEET_ZONE of
## c fights; auto-resolved at once (resolve()). Returns the ids involved.
static func sea_battle(st: Dictionary, mover: Dictionary, foes: Array, c: int) -> Dictionary:
	var f := int(mover["f"])
	var att: Array = []
	var dfn: Array = []
	for e in fleets(st):
		if not CGrid.within(c, cell(e), FLEET_ZONE) and e != mover:
			continue
		if CState.friendly(st, f, int(e["f"])):
			att.append(e)
		elif foes.has(e) or CState.at_war(st, f, int(e["f"])):
			dfn.append(e)
	var ids := {}
	for e in att + dfn:
		ids[int(e["id"])] = 1
		_drop_voyage(e)
		e["moved"] = 1
	resolve(st, att, dfn, c)
	return ids


static func _side_power(st: Dictionary, side: Array, defending: bool) -> int:
	var p := 0
	for fl in side:
		p += power(fl)
	if defending and not side.is_empty():
		var best := 0
		for fl in side:
			var r := port_of(st, fl, int(fl["f"]))
			if r >= 0:
				best = maxi(best, PORT_DEF_PCT + PORT_WALL_PCT * CState.walls(st, r))
		if best > 0:
			p = p * best / 100
	return p


## Auto-resolve a sea battle between fleets att and dfn at cell c (the
## formula: power x a roll each; the loser's ships are sunk or taken by its
## margin, the winner's damaged by the loser's share; fleets without ships
## sink with everyone aboard; troops beyond what the survivors carry drown;
## the loser's fleets fall back). Event "sea_battle".
static func resolve(st: Dictionary, att: Array, dfn: Array, c: int) -> void:
	var pa := _side_power(st, att, false)
	var pd := _side_power(st, dfn, true)
	var va := pa * (ROLL_MIN + CState.rand(st, ROLL_SPAN)) / 100
	var vd := pd * (ROLL_MIN + CState.rand(st, ROLL_SPAN)) / 100
	var att_won := va > vd
	var win: Array = att if att_won else dfn
	var lose: Array = dfn if att_won else att
	var wv := va if att_won else vd
	var lv := vd if att_won else va
	var share := wv * 100 / maxi(wv + lv, 1)
	var wf := int(win[0]["f"]) if not win.is_empty() else -1
	var pirate := wf >= 0 and PIRATES.has(str(CData.FACTIONS[wf]["key"]))
	var cap_pct := PIRATE_CAPTURE_PCT if pirate else CAPTURE_PCT
	var lost: Array = []   # [faction, ship key, 0 sunk / 1 taken]
	var prizes: Array = []
	var loss_pct := clampi(LOSS_BASE + 2 * (share - 50), LOSS_BASE, LOSS_MAX)
	for fl in lose:
		var keep: Array = []
		for s in fl["ships"]:
			var row := CData.ship_row(str(s["t"]))
			if CState.rand(st, 100) < loss_pct:
				var taken := int(row.get("oars", 0)) == 0 and CState.rand(st, 100) < cap_pct
				lost.append([int(fl["f"]), str(s["t"]), 1 if taken else 0])
				if taken:
					prizes.append({"t": str(s["t"]), "h": TAKEN_PCT, "c": TAKEN_PCT})
				continue
			s["h"] = int(s["h"]) - 15 - CState.rand(st, 25)
			s["c"] = maxi(int(s["c"]) - 10 - CState.rand(st, 20), 5)
			if int(s["h"]) <= 0:
				lost.append([int(fl["f"]), str(s["t"]), 0])
				continue
			keep.append(s)
		fl["ships"] = keep
	var dmg := (100 - share) * 6 / 10
	for fl in win:
		var keep2: Array = []
		for s in fl["ships"]:
			s["h"] = int(s["h"]) - dmg - CState.rand(st, 10)
			s["c"] = maxi(int(s["c"]) - dmg / 2 - CState.rand(st, 8), 5)
			if int(s["h"]) <= 0:
				lost.append([int(fl["f"]), str(s["t"]), 0])
				continue
			keep2.append(s)
		fl["ships"] = keep2
	if not win.is_empty() and not prizes.is_empty():
		(win[0]["ships"] as Array).append_array(prizes)
	var sunk: Array = []   # [faction, army id, units]
	for fl in att + dfn:
		_sink_extra(st, fl, sunk)
	var gone: Array = []
	for fl in att + dfn:
		if (fl["ships"] as Array).is_empty():
			gone.append(fl)
	for fl in lose:
		if not gone.has(fl):
			_fall_back(st, fl, c, win)
	for fl in gone:
		(st["fleets"] as Array).erase(fl)
	var af: Array = []
	var df: Array = []
	var aid: Array = []
	var did: Array = []
	for fl in att:
		aid.append(int(fl["id"]))
		if not af.has(int(fl["f"])):
			af.append(int(fl["f"]))
	for fl in dfn:
		did.append(int(fl["id"]))
		if not df.has(int(fl["f"])):
			df.append(int(fl["f"]))
	var stats: Dictionary = st["stats"]
	stats["sea_battles"] = int(stats.get("sea_battles", 0)) + 1
	_rules().event(st, {"k": "sea_battle", "x": CGrid.cx(c), "y": CGrid.cy(c), "att": af, "def": df, "af": aid,
		"df": did, "won": 0 if att_won else 1, "pa": pa, "pd": pd, "lost": lost, "taken": prizes.size(),
		"sunk": sunk, "auto": 1})


## Troops beyond what fleet fl's ships now carry drown (the last aboard
## first; a fleet without ships loses everyone): [faction, army id, units]
## appended to `sunk`.
static func _sink_extra(st: Dictionary, fl: Dictionary, sunk: Array) -> void:
	var cap := capacity(fl)
	var carry: Array = fl["carry"]
	while not carry.is_empty() and carried_units(fl) > cap:
		var a: Dictionary = carry.pop_back()
		sunk.append([int(a["f"]), int(a["id"]), CState.unit_count(a)])
		_rules().event(st, {"k": "army_sunk", "f": int(a["f"]), "army": int(a["id"]), "units": CState.unit_count(a)})


## The beaten fleet fl falls back: the sea cell within RETREAT_R of the
## battle's cell c farthest from it, outside the winners' zones (ties by
## cell index); it stays when there is none.
static func _fall_back(_st: Dictionary, fl: Dictionary, c: int, win: Array) -> void:
	var lim := int(CData.ship_const("COASTAL_CELLS", 2))
	var coast := coastal(fl)
	var best := -1
	var bd := -1
	for j in CGrid.disc(cell(fl), RETREAT_R):
		if not is_sea(j) or (coast and coast_dist(j) > lim):
			continue
		var ok := true
		for e in win:
			if CGrid.within(cell(e), j, FLEET_ZONE):
				ok = false
				break
		if not ok:
			continue
		var d := CGrid.d2(j, c)
		if d > bd:
			bd = d
			best = j
	if best >= 0:
		place(fl, best)


# ------------------------------------------------------------ end of turn ---

## End of turn: ships ordered this turn are launched (they join a fleet of
## ours at the dock, else form one), fleets in an own port are repaired,
## fleets at sea lose crew (scurvy), the fleets of dead factions go;
## every fleet may sail again.
static func end_of_turn(st: Dictionary) -> void:
	if not on(st):
		return
	for r in CData.region_count():
		var rs: Dictionary = st["regions"][r]
		if not rs.has("sq"):
			continue
		var o := int(rs["owner"])
		var q: Array = rs["sq"]
		rs.erase("sq")
		if o < 0 or dock(r) < 0:
			continue
		for key in q:
			var ship := {"t": str(key), "h": 100, "c": 100}
			var into := {}
			for fl in fleets(st):
				if int(fl["f"]) == o and CGrid.cheb(cell(fl), dock(r)) <= 1:
					into = fl
					break
			if into.is_empty():
				into = _new_fleet(st, o, dock(r), [ship])
			else:
				(into["ships"] as Array).append(ship)
			_rules().event(st, {"k": "ship_built", "f": o, "r": r, "ship": str(key), "fleet": int(into["id"])})
	var keep: Array = []
	for fl in fleets(st):
		var f := int(fl["f"])
		if not CState.alive(st, f) or (fl["ships"] as Array).is_empty():
			continue
		var r := port_of(st, fl, f)
		for s in fl["ships"]:
			if r >= 0:
				var add := REPAIR + REPAIR_YARD * CState.building(st, r, CData.SHIPYARD)
				s["h"] = mini(int(s["h"]) + add, 100)
				s["c"] = mini(int(s["c"]) + add, 100)
			elif int(s["c"]) > SCURVY_FLOOR:
				s["c"] = maxi(int(s["c"]) - SCURVY, SCURVY_FLOOR)
		fl["moved"] = 0
		keep.append(fl)
	st["fleets"] = keep


## Faction f is eliminated: its fleets go down with it.
static func drop_faction(st: Dictionary, f: int) -> void:
	if not on(st):
		return
	var keep: Array = []
	for fl in fleets(st):
		if int(fl["f"]) != f:
			keep.append(fl)
	st["fleets"] = keep


## The last turn's fleet steps (the replay): [[fleet id, cell], ...].
static func last_steps(st: Dictionary) -> Array:
	var out: Array = []
	for e in st.get("events", []):
		if str(e.get("k", "")) == "fmoves" and int(e["turn"]) == int(st["turn"]) - 1:
			out.append_array(e["steps"])
	return out
