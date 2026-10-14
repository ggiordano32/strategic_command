extends RefCounted
## Campaign AI for fleets (N1, a pack with ships; called from CAI.act before
## the land moves are planned). Deterministic: reads the state, acts through
## the same orders as the players, the state's RNG only, index order.
##
## Each AI turn of faction f:
##  1. debt: a ship without troops aboard is scuttled while in debt; fleets
##     of ours side by side and empty merge;
##  2. build: a Shipyard 1 at its best port when it has none; at most one
##     ship a turn: transports while the fleets carry less than WANT_CAP
##     units (by its armies), else warships while its fleets are weaker than
##     its enemies' (WAR_PCT), within the money above the AI's reserve;
##  3. loaded fleets sail to land their troops by the best hostile coastal
##     region they can take (value per defence, the voyage in turns), or the
##     nearest friendly coast with work on that land;
##  4. empty fleets attack enemy fleets at war they reach this turn when
##     ours is ATTACK_PCT stronger;
##  5. transport: an army with nothing to do on its land (no hostile region
##     there, or idle IDLE_TURNS turns and not needed at home) that fits a
##     free fleet: beside it, it boards and sails (3.); else the fleet sails
##     to the coast cell nearest the army and the army marches there (it is
##     kept out of the land plans: CAI.fleet_reserved);
##  6. the rest go home to a port of ours when damaged or when a stronger
##     enemy fleet is near (no suicide); voyages avoid enemy fleets' zones.
## Distances for choices are straight-line estimates (octile cells at the
## fleet's mean pace); only the chosen voyage is searched (CFleet.plan).

const CData := preload("res://campaign/cdata.gd")
const CState := preload("res://campaign/cstate.gd")
const CRules := preload("res://campaign/crules.gd")
const CGrid := preload("res://campaign/cgrid.gd")
const CFleet := preload("res://campaign/cfleet.gd")
const CAI := preload("res://campaign/cai.gd")

const ATTACK_PCT := 140      # attack an enemy fleet with this % of its power
const LAND_PCT := 110        # land against a region whose defence the troops beat by this %
const IDLE_TURNS := 4
const WAR_PCT := 100         # warships while ours < this % of the strongest enemy's fleets
const DANGER_PCT := 120      # an enemy fleet this % of ours within DANGER_CELLS sends ours home
const DANGER_CELLS := 30
const DAMAGED_PCT := 60      # mean hull below this: home for repairs
const MAX_SHIPS := 14
const MAX_TURNS := 8         # landings further than this (estimated turns) are not considered


static func act(st: Dictionary, f: int, moves: Array, fmoves: Array) -> void:
	if not CFleet.on(st) or not CState.alive(st, f):
		return
	_debt(st, f)
	_merge(st, f)
	_build(st, f)
	var mine: Array = []
	for fl in CFleet.fleets_of(st, f):
		if int(fl["moved"]) == 0 and not (fl["ships"] as Array).is_empty():
			mine.append(fl)
	if mine.is_empty():
		return
	var cx := CAI._context6(st, f)
	var used := {}
	var reserved: Dictionary = CAI.fleet_reserved
	# Transport first: boarding now changes what is loaded.
	var cands := _stranded(st, f, cx)
	var taken := {}
	for fl in mine:
		if not (fl["carry"] as Array).is_empty():
			continue
		var a := _pick_army(st, fl, cands, taken)
		if a.is_empty():
			fl.erase("job")
			continue
		var id := int(a["id"])
		taken[id] = 1
		fl["job"] = id
		if CFleet.near_fleet(a, fl):
			if CRules.apply_order(st, f, {"t": "embark", "army": id, "fleet": int(fl["id"])}) == "":
				fl.erase("job")
			continue
		var p := _coast_for(st, a)
		if p < 0 or not _approach(st, fl, p):
			fl.erase("job")
			continue
		reserved[id] = 1
		if CState.cell(a) != p:
			moves.append([id, p, f, CData.MODE_SIEGE, 0, -1])
		used[int(fl["id"])] = 1
		if CGrid.cheb(CFleet.cell(fl), p) > 1:
			var sea := _sea_by(st, fl, p)
			if sea >= 0:
				fmoves.append([int(fl["id"]), sea, f, 0, -1])
	# Loaded fleets land.
	for fl in mine:
		if (fl["carry"] as Array).is_empty() or used.has(int(fl["id"])):
			continue
		used[int(fl["id"])] = 1
		var dest := _landing(st, f, fl)
		if dest >= 0:
			fmoves.append([int(fl["id"]), dest, f, 0, -1])
	# Attacks.
	for fl in mine:
		if used.has(int(fl["id"])) or not (fl["carry"] as Array).is_empty():
			continue
		var tgt := _prey(st, f, fl)
		if tgt >= 0:
			used[int(fl["id"])] = 1
			fmoves.append([int(fl["id"]), -1, f, 0, tgt])
	# Home: damaged, or a stronger enemy near.
	for fl in mine:
		if used.has(int(fl["id"])) or CFleet.port_of(st, fl, f) >= 0:
			continue
		if _hull(fl) >= DAMAGED_PCT and not _danger(st, f, fl):
			continue
		var home := _home(st, f, fl)
		if home >= 0:
			fmoves.append([int(fl["id"]), home, f, 0, -1])


# ----------------------------------------------------------------- money ---

static func _debt(st: Dictionary, f: int) -> void:
	if int(st["factions"][f]["treasury"]) >= 0:
		return
	var best := {}
	var bk := -1
	var bp := 1 << 30
	for fl in CFleet.fleets_of(st, f):
		if not (fl["carry"] as Array).is_empty():
			continue
		for k in (fl["ships"] as Array).size():
			var p := CFleet.ship_power(fl["ships"][k])
			if p < bp:
				bp = p
				best = fl
				bk = k
	if bk >= 0:
		CRules.apply_order(st, f, {"t": "scuttle", "fleet": int(best["id"]), "ship": bk})


static func _merge(st: Dictionary, f: int) -> void:
	var list := CFleet.fleets_of(st, f)
	for i in list.size():
		var a: Dictionary = list[i]
		if not CFleet.fleet(st, int(a["id"])).is_empty() and int(a["moved"]) == 0 and (a["carry"] as Array).is_empty():
			for j in range(i + 1, list.size()):
				var b: Dictionary = list[j]
				if CFleet.fleet(st, int(b["id"])).is_empty() or int(b["moved"]) != 0 or not (b["carry"] as Array).is_empty():
					continue
				if CGrid.cheb(CFleet.cell(a), CFleet.cell(b)) <= 1 and CFleet.coastal(a) == CFleet.coastal(b):
					CRules.apply_order(st, f, {"t": "fmerge", "fleet": int(b["id"]), "into": int(a["id"])})


static func _build(st: Dictionary, f: int) -> void:
	var budget := int(st["factions"][f]["treasury"]) - CAI._reserve(st, f)
	if budget <= 0:
		return
	var ports: Array[int] = []
	for r in CState.regions_of(st, f):
		if CFleet.dock(r) >= 0:
			ports.append(r)
	if ports.is_empty():
		return
	ports.sort_custom(func(a, b):
		var va := CState.building(st, a, CData.SHIPYARD) * 100 + (50 if CData.is_capital(a) else 0) + CAI.region_value(st, a, f)
		var vb := CState.building(st, b, CData.SHIPYARD) * 100 + (50 if CData.is_capital(b) else 0) + CAI.region_value(st, b, f)
		return va > vb or (va == vb and a < b))
	# A shipyard at the best port when there is none (and the people sail).
	var fk := str(CData.FACTIONS[f]["key"])
	var yard_ships := false
	for row in CData.ship_rows():
		if (row["factions"] as Array).has(fk) and int(row["yard"]) > 0:
			yard_ships = true
	var has_yard := false
	for r in ports:
		if CState.building(st, r, CData.SHIPYARD) > 0:
			has_yard = true
	if yard_ships and not has_yard:
		var info := CRules.build_info(st, f, ports[0], CData.SHIPYARD)
		if not info.has("why") and int(info["cost"]) <= budget:
			CRules.apply_order(st, f, {"t": "build", "r": ports[0], "chain": CData.SHIPYARD})
		return
	var cap := 0
	var pw := 0
	var ships := 0
	for fl in CFleet.fleets_of(st, f):
		cap += CFleet.capacity(fl)
		pw += CFleet.power(fl)
		ships += (fl["ships"] as Array).size()
	if ships >= MAX_SHIPS:
		return
	var foe := 0
	for g in CAI.wars(st, f):
		var p := 0
		for fl in CFleet.fleets_of(st, g):
			p += CFleet.power(fl)
		foe = maxi(foe, p)
	var want_cap := clampi(2 + 2 * CState.armies_of(st, f).size(), 3, 10)
	var transport := cap < want_cap
	if not transport and pw * 100 >= foe * WAR_PCT:
		return
	var best_r := -1
	var best_k := ""
	var best_v := -1
	for r in ports:
		for key in CFleet.buildable(st, f, r):
			var row := CData.ship_row(str(key))
			if int(row["cost"]) > budget or CFleet.ship_check(st, f, r, str(key)) != "":
				continue
			var v := int(row["cap"]) * 1000 + int(row["guns"]) if transport else int(row["guns"]) * 1000 + int(row["cap"])
			if v > best_v:
				best_v = v
				best_k = str(key)
				best_r = r
	if best_r >= 0:
		CRules.apply_order(st, f, {"t": "ship", "r": best_r, "ship": best_k})


# -------------------------------------------------------------- transport ---

## Armies of f with nothing to do on their land: no hostile region on their
## landmass, or idle IDLE_TURNS turns; not in a battle or a siege, not
## needed to hold their region.
static func _stranded(st: Dictionary, f: int, cx: Dictionary) -> Array:
	var work := {}
	for r in CData.region_count():
		if CState.at_war(st, f, CState.owner(st, r)):
			work[int(CData.REGIONS[r]["land"])] = 1
	var out: Array = []
	for a in CState.armies_of(st, f):
		if int(a["busy"]) != 0 or CRules.siege_role(st, a) != 0 or CState.unit_count(a) < 2:
			continue
		var land := int(CData.REGIONS[int(a["r"])]["land"])
		if work.has(land) and int(a.get("idle", 0)) < IDLE_TURNS:
			continue
		if CAI._hold(cx, st, f, a):
			continue
		out.append(a)
	return out


## The army fleet fl fetches: its job if still a candidate, else the nearest
## candidate (straight line) that fits aboard, not taken by another fleet.
static func _pick_army(_st: Dictionary, fl: Dictionary, cands: Array, taken: Dictionary) -> Dictionary:
	var cap := CFleet.capacity(fl)
	var job := int(fl.get("job", -1))
	for a in cands:
		if int(a["id"]) == job and not taken.has(job) and CState.unit_count(a) <= cap:
			return a
	var best := {}
	var bd := 1 << 30
	for a in cands:
		if taken.has(int(a["id"])) or CState.unit_count(a) > cap:
			continue
		var d := CGrid.octile(CFleet.cell(fl), CState.cell(a))
		if d < bd:
			bd = d
			best = a
	return best


## The coast cell where army a meets its fleet: its region's beach, else
## its landmass's beach nearest it (straight line), -1 none.
static func _coast_for(st: Dictionary, a: Dictionary) -> int:
	var r := int(a["r"])
	var b := CFleet.beach(r)
	if b >= 0 and CFleet.land_ok(st, int(a["f"]), b):
		return b
	var land := int(CData.REGIONS[r]["land"])
	var best := -1
	var bd := 1 << 30
	for k in CData.region_count():
		var bk := CFleet.beach(k)
		if bk < 0 or int(CData.REGIONS[k]["land"]) != land or not CFleet.land_ok(st, int(a["f"]), bk):
			continue
		if not CState.friendly(st, int(a["f"]), CState.owner(st, k)):
			continue
		var d := CGrid.d2(bk, CState.cell(a))
		if d < bd:
			bd = d
			best = bk
	return best


## Fleet fl can come beside land cell b (a free sea cell beside it, along
## the coast for a coastal fleet).
static func _approach(st: Dictionary, fl: Dictionary, b: int) -> bool:
	var sea := _sea_by(st, fl, b)
	return sea >= 0 and (not CFleet.coastal(fl) or CFleet.coastal_link(CFleet.cell(fl), sea))


## A sea cell beside land cell p for fleet fl (outside enemy zones), -1 none.
static func _sea_by(st: Dictionary, fl: Dictionary, p: int) -> int:
	var lim := int(CData.ship_const("COASTAL_CELLS", 2))
	for k in 8:
		var j := CGrid.at(CGrid.cx(p) + CGrid.DX[k], CGrid.cy(p) + CGrid.DY[k])
		if j >= 0 and CFleet.is_sea(j) and CFleet.zone_owner(st, int(fl["f"]), j) < 0 \
				and not (CFleet.coastal(fl) and CFleet.coast_dist(j) > lim):
			return j
	return -1


## Turns fleet fl needs to cell c (a straight-line estimate at a beam pace).
static func _turns(fl: Dictionary, c: int) -> int:
	var sp := maxi(CFleet.speed(fl), 1)
	return CGrid.octile(CFleet.cell(fl), c) / sp


static func _carried_strength(fl: Dictionary) -> int:
	var s := 0
	for a in fl["carry"]:
		s += CState.strength(a)
	return s


## Where loaded fleet fl sails to land (a coast cell: CFleet.plan lands on
## arriving), -1 none. The best hostile region it can take, by value per
## defence and the voyage; else the nearest friendly coast on a landmass
## with hostile regions.
static func _landing(st: Dictionary, f: int, fl: Dictionary) -> int:
	var s := _carried_strength(fl)
	var best := -1
	var bv := -1
	for t in CData.region_count():
		var o := CState.owner(st, t)
		var b := CFleet.beach(t)
		if b < 0 or not CState.at_war(st, f, o) or not CState.battle_at(st, t).is_empty() \
				or not CState.siege_at(st, t).is_empty():
			continue
		var d := maxi(CAI.target_defence(st, f, t), 1)
		if s * 100 < d * LAND_PCT or not _approach(st, fl, b):
			continue
		var tt := _turns(fl, b)
		if tt > MAX_TURNS:
			continue
		var v := CAI.region_value(st, t, f) * 1000 / d / (1 + tt)
		if v > bv:
			bv = v
			best = t
	if best >= 0:
		return CFleet.beach(best)
	var work := {}
	for r in CData.region_count():
		if CState.at_war(st, f, CState.owner(st, r)):
			work[int(CData.REGIONS[r]["land"])] = 1
	var bd := 1 << 30
	var home := -1
	var here := int(CData.REGIONS[int(fl["carry"][0]["r"])]["land"])
	for r in CData.region_count():
		var b := CFleet.beach(r)
		var land := int(CData.REGIONS[r]["land"])
		if b < 0 or not work.has(land) or land == here or not CState.friendly(st, f, CState.owner(st, r)) \
				or not _approach(st, fl, b):
			continue
		var d := CGrid.octile(CFleet.cell(fl), b)
		if d < bd:
			bd = d
			home = b
	return home


# ---------------------------------------------------------------- fights ---

## An enemy fleet at war fl reaches this turn and beats by ATTACK_PCT (the
## weakest such, ties by id), -1 none.
static func _prey(st: Dictionary, f: int, fl: Dictionary) -> int:
	var mine := CFleet.power(fl)
	var best := -1
	var bp := 1 << 30
	for e in CFleet.fleets(st):
		if not CState.at_war(st, f, int(e["f"])):
			continue
		var ep := CFleet.power(e)
		if mine * 100 < ep * ATTACK_PCT or _turns(fl, CFleet.cell(e)) > 0:
			continue
		if CFleet.coastal(fl) and not CFleet.coastal_link(CFleet.cell(fl), CFleet.cell(e)):
			continue
		if ep < bp:
			bp = ep
			best = int(e["id"])
	return best


static func _hull(fl: Dictionary) -> int:
	var n := 0
	var h := 0
	for s in fl["ships"]:
		h += int(s["h"])
		n += 1
	return h / maxi(n, 1)


static func _danger(st: Dictionary, f: int, fl: Dictionary) -> bool:
	var mine := CFleet.power(fl)
	for e in CFleet.fleets(st):
		if CState.at_war(st, f, int(e["f"])) and CFleet.power(e) * 100 > mine * DANGER_PCT \
				and CGrid.cheb(CFleet.cell(e), CFleet.cell(fl)) <= DANGER_CELLS:
			return true
	return false


## The dock of our port nearest fleet fl (straight line), -1 none.
static func _home(st: Dictionary, f: int, fl: Dictionary) -> int:
	var best := -1
	var bd := 1 << 30
	for r in CState.regions_of(st, f):
		var dk := CFleet.dock(r)
		if dk < 0 or CFleet.zone_owner(st, f, dk) >= 0 or (CFleet.coastal(fl) and not CFleet.coastal_link(CFleet.cell(fl), dk)):
			continue
		var d := CGrid.octile(CFleet.cell(fl), dk)
		if d < bd:
			bd = d
			best = dk
	return best
