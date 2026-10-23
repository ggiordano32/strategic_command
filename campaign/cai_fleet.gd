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
##     kept out of the land plans: CAI.fleet_reserved). (Garrisons against
##     landings, docs/AI.md 12.2, 2026-10-23) "Not needed at home" counts the
##     troops hostile fleets can land (CAI._sea_threat, CAI.needed_home: what
##     stays must cover SEA_AWAY_PCT of the threat a turn ahead), and no army
##     boards, nor does a loaded fleet sail to land (3.), while the fleets at
##     war within a turn's sail of the route outgun the carrier beyond
##     FERRY_ODDS_PCT (_ferry_safe); a loaded fleet with nowhere safe to land
##     waits, or runs home in danger (7.);
##  6. (N2) free fleets in good repair blockade the richest enemy port
##     within BLOCKADE_TURNS whose defenders they outgun by SAFE_PCT (a
##     station on its approach, outside enemy zones), or keep the one they
##     hold; pirates hunt the flota (FLOTA_PCT, within FLOTA_TURNS) and
##     prefer weak, rich prey; the nations hunt pirate fleets harder by
##     their infamy; the flota itself sails by the rules (CSea);
##     (lanes, 2026-10-22) a free fleet weaker than the fleets of the factions
##     at war with it RAIDS instead: the richest enemy lane in reach (the
##     value its enemies' ports pay, by the turns to reach it), holding the
##     lane cell it lies on; not at Easy, and never with an enemy fleet
##     within RAID_FLEE_CELLS. At Skilled the ports under our own land siege
##     are the blockades' first choice;
##  7. the rest go home to a port of ours when damaged or when a stronger
##     enemy fleet is near (no suicide); voyages avoid enemy fleets' zones;
##  8. (N2b) hurricanes: a fleet at sea in a storm's forecast cone runs for
##     a safe port it reaches this turn, else for clear water out of the
##     cone; one in port with a storm coming rides it out there; while
##     storms are about, fleets in port start no blockade, and no voyage
##     (prey, blockade station, landing, pick-up, home) ends in a cone.
##  9. (Docking, 2026-10-23) a free fleet with no job lying on the dock of a
##     port of ours (or a patron's) docks there (an at-once fdock: sheltered,
##     the yard repairs it); a home voyage (7.) docks on arriving; a fleet
##     given any voyage casts off by it. Docked fleets are not prey.
## 10. (Sorties, docs/AI.md 12.4, 2026-10-23) before the attacks (4.): at each
##     port where fleets of ours lie docked, the strongest of them in good
##     repair and empty comes out against an enemy fleet at war lying within
##     BLOCKADE_CELLS + SORTIE_REACH of the harbour (not docked, not in a
##     pending battle; the port's blockader first) when it has SORTIE_ODDS_PCT
##     of the enemy's power at the spot (SORTIE_HUNT_PCT for a fleet merely
##     passing; Skilled only); Easy never. Next turn it follows the rules above.
## Distances for choices are straight-line estimates (octile cells at the
## fleet's mean pace); only the chosen voyage is searched (CFleet.plan).

const CData := preload("res://campaign/cdata.gd")
const CState := preload("res://campaign/cstate.gd")
const CRules := preload("res://campaign/crules.gd")
const CGrid := preload("res://campaign/cgrid.gd")
const CFleet := preload("res://campaign/cfleet.gd")
const CAI := preload("res://campaign/cai.gd")
const CSea := preload("res://campaign/csea.gd")
const CStorm := preload("res://campaign/cstorm.gd")
const CLanes := preload("res://campaign/clanes.gd")
const CP := preload("res://campaign/cai_profile.gd")

const ATTACK_PCT := 140      # attack an enemy fleet with this % of its power
const LAND_PCT := 110        # (until 2026-10-22: land where the troops beat the defence by this %; now the level's ATTACK_WIN chance)
const IDLE_TURNS := 4
const WAR_PCT := 100         # warships while ours < this % of the strongest enemy's fleets
const DANGER_PCT := 120      # an enemy fleet this % of ours within DANGER_CELLS sends ours home
const DANGER_CELLS := 30
const DAMAGED_PCT := 60      # mean hull below this: home for repairs
const MAX_SHIPS := 14
const MAX_TURNS := 8         # landings further than this (estimated turns) are not considered
const BLOCKADE_TURNS := 3    # (N2) blockade ports at most this far (estimated turns)
const SAFE_PCT := 130        # ... whose defenders near the harbour we outgun by this %
const BLOCKADE_HULL := 70    # ... with a mean hull of at least this
const GUARD_CELLS := 30      # defenders counted within this of the harbour (a turn's sail)
const FLOTA_PCT := 110       # attack the flota with this % of its power (pirates PIRATE_FLOTA_PCT)
const PIRATE_FLOTA_PCT := 90
const FLOTA_TURNS := 3       # ... within this many estimated turns (pirates; nations 2)
const RAID_TURNS := 4        # (lanes) raid lanes whose nearest station is at most this far (estimated turns)
const RAID_FLEE_CELLS := 2   # ... and stop raiding when an enemy fleet at war comes this near
const PIRATE_ATTACK_PCT := 130
const PIRATE_DAMAGED_PCT := 75  # pirates make for a haven sooner ...
const PIRATE_DANGER_PCT := 100  # ... and shun any navy their match


## Memos of one act (the fleets do not change while it plans): fleet id ->
## power, region -> its side's guard, the hostile harbours.
static var _pw := {}
static var _gd := {}
static var _hostile_hb: Array[int] = []
static var _stormy := false  # (N2b) storms about this act


## (N2b) Cell c lies in a storm's forecast cone (one cell of margin).
static func _storm_at(st: Dictionary, c: int) -> bool:
	return _stormy and CStorm.danger(st, c, 1)


## Fleet e's power (memo of this act).
static func _power(e: Dictionary) -> int:
	var id := int(e["id"])
	if not _pw.has(id):
		_pw[id] = CFleet.power(e)
	return int(_pw[id])


static func act(st: Dictionary, f: int, moves: Array, fmoves: Array, cx_in: Dictionary = {}) -> void:
	if not CFleet.on(st) or not CState.alive(st, f):
		return
	_debt(st, f)
	_merge(st, f)
	_build(st, f)
	_pw = {}
	_gd = {}
	_hostile_hb = []
	for r in CData.region_count():
		if CFleet.harbour(r) >= 0 and CState.at_war(st, f, CState.owner(st, r)):
			_hostile_hb.append(CFleet.harbour(r))
	var mine: Array = []
	for fl in CFleet.fleets_of(st, f):
		if int(fl["moved"]) == 0 and not (fl["ships"] as Array).is_empty() and not CSea.is_flota(fl) and not fl.has("sto"):
			mine.append(fl)  # ("sto": a story campaign's fleet, campaign/cstory.gd, sails by the story)
	if mine.is_empty():
		return
	var cx := cx_in if not cx_in.is_empty() else CAI._context6(st, f)
	var used := {}
	var reserved: Dictionary = CAI.fleet_reserved
	# (N2b) Hurricanes first: run from a forecast cone, or ride it out in port.
	_stormy = not CStorm.storms(st).is_empty()
	if _stormy:
		for fl in mine:
			var here := CFleet.cell(fl)
			if not _storm_at(st, here):
				continue
			used[int(fl["id"])] = 1
			fl.erase("job")
			if CFleet.port_of(st, fl, f, true) >= 0:
				continue
			var to := _shelter(st, f, fl)
			if to >= 0:
				fmoves.append([int(fl["id"]), to, f, 0, -1])
	# The flota first (N2): every empty fleet that can catch a treasure fleet.
	for fl in mine:
		if not (fl["carry"] as Array).is_empty():
			continue
		var tt := _prey(st, f, fl, true)
		if tt >= 0:
			used[int(fl["id"])] = 1
			fl.erase("job")
			var ic := _intercept(st, fl, CFleet.fleet(st, tt))
			if ic >= 0:
				fmoves.append([int(fl["id"]), ic, f, 0, -1])  # lie across its course
			else:
				fmoves.append([int(fl["id"]), -1, f, 0, tt])
	# Transport: boarding now changes what is loaded.
	var cands := _stranded(st, f, cx)
	var taken := {}
	for fl in mine:
		if not (fl["carry"] as Array).is_empty() or used.has(int(fl["id"])):
			continue
		var a := _pick_army(st, fl, cands, taken)
		if a.is_empty():
			fl.erase("job")
			continue
		var id := int(a["id"])
		taken[id] = 1
		var p0 := CState.cell(a) if CFleet.near_fleet(a, fl) else _coast_for(st, a)
		if not _ferry_safe(st, f, fl, [CFleet.cell(fl), p0]):
			fl.erase("job")  # (a stronger navy within a turn's sail: the army stays ashore)
			CP.count(CP.C_FERRY_REFUSED, f)
			continue
		fl["job"] = id
		if CFleet.near_fleet(a, fl):
			if CRules.apply_order(st, f, {"t": "embark", "army": id, "fleet": int(fl["id"])}) == "":
				fl.erase("job")
			cx.erase("cover")  # (CAI.needed_home's memo: an army has left)
			continue
		var p := _coast_for(st, a)
		if p < 0 or not _approach(st, fl, p) or _storm_at(st, p):
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
		var dest := _landing(st, f, fl)
		if dest >= 0:
			used[int(fl["id"])] = 1
			fmoves.append([int(fl["id"]), dest, f, 0, -1])
		elif not _danger(st, f, fl):
			used[int(fl["id"])] = 1  # (nowhere safe to land: wait; in danger it runs home below)
	# (Sorties) docked fleets come out against a fleet lying off their port.
	_sorties(st, f, mine, used, fmoves)
	# Attacks.
	for fl in mine:
		if used.has(int(fl["id"])) or not (fl["carry"] as Array).is_empty():
			continue
		var tgt := _prey(st, f, fl)
		if tgt >= 0:
			used[int(fl["id"])] = 1
			fmoves.append([int(fl["id"]), -1, f, 0, tgt])
	# Blockades (N2): the richest enemy port in reach whose guard we outgun.
	# Raids (lanes): a weaker navy's play, the richest enemy lane in reach.
	var taken_ports := {}
	var taken_lanes := {}
	var rt := CLanes.raiders(st)
	var foe_power := _foe_power(st, f)
	for fl in mine:
		if used.has(int(fl["id"])) or not (fl["carry"] as Array).is_empty():
			continue
		if _hull(fl) < BLOCKADE_HULL or _danger(st, f, fl):
			continue
		if _stormy and CFleet.port_of(st, fl, f, true) >= 0:
			continue  # (N2b) the season: stay in port while storms are about
		if _power(fl) < foe_power and CP.skill(st, f) > CP.EASY:
			var rp := _raid(st, f, fl, taken_lanes, rt)
			if not rp.is_empty():
				used[int(fl["id"])] = 1
				taken_lanes[int(rp[0])] = 1
				if int(rp[1]) != CFleet.cell(fl):
					fmoves.append([int(fl["id"]), int(rp[1]), f, 0, -1])
				continue
		var bp := _blockade(st, f, fl, taken_ports)
		if bp.is_empty():
			continue
		used[int(fl["id"])] = 1
		taken_ports[int(bp[0])] = 1
		if int(bp[1]) != CFleet.cell(fl):
			fmoves.append([int(fl["id"]), int(bp[1]), f, 0, -1])
	# Home: damaged, or a stronger enemy near.
	for fl in mine:
		if used.has(int(fl["id"])) or CFleet.port_of(st, fl, f) >= 0:
			continue
		if _hull(fl) >= (PIRATE_DAMAGED_PCT if CSea.pirate(f) else DAMAGED_PCT) and not _danger(st, f, fl):
			continue
		var home := _home(st, f, fl)
		if home >= 0:
			fmoves.append([int(fl["id"]), home, f, 0, -1, CFleet.dock_region(st, f, home)])
	# (Docking) the free fleets lying at a dock of ours with nothing to do dock there.
	var sailing := {}
	for m in fmoves:
		sailing[int(m[0])] = 1
	for fl in mine:
		if sailing.has(int(fl["id"])) or used.has(int(fl["id"])) or CFleet.docked(fl) >= 0 or fl.has("job") \
				or not (fl["carry"] as Array).is_empty():
			continue
		var dr := CFleet.dock_region(st, f, CFleet.cell(fl))
		if dr >= 0:
			CRules.apply_order(st, f, {"t": "fdock", "fleet": int(fl["id"]), "r": dr})


# ----------------------------------------------------------------- money ---

static func _debt(st: Dictionary, f: int) -> void:
	if int(st["factions"][f]["treasury"]) >= 0:
		return
	var best := {}
	var bk := -1
	var bp := 1 << 30
	for fl in CFleet.fleets_of(st, f):
		if not (fl["carry"] as Array).is_empty() or CSea.is_flota(fl) or fl.has("busy") or fl.has("sto"):
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
		if CSea.is_flota(a) or a.has("sto"):
			continue
		if not CFleet.fleet(st, int(a["id"])).is_empty() and int(a["moved"]) == 0 and (a["carry"] as Array).is_empty():
			for j in range(i + 1, list.size()):
				var b: Dictionary = list[j]
				if CFleet.fleet(st, int(b["id"])).is_empty() or int(b["moved"]) != 0 or not (b["carry"] as Array).is_empty() \
						or CSea.is_flota(b) or b.has("sto"):
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
	var pv := {}
	for r in ports:
		pv[r] = CState.building(st, r, CData.SHIPYARD) * 100 + (50 if CData.is_capital(r) else 0) + CAI.region_value(st, r, f)
	ports.sort_custom(func(a, b):
		return int(pv[a]) > int(pv[b]) or (int(pv[a]) == int(pv[b]) and a < b))
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
		if CSea.is_flota(fl):
			continue
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
			if int(row.get("fire", 0)) != 0:
				continue  # (N3c: fire ships are a player's choice; the battle AI sails them)
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
		if CState.at_war(st, f, CState.owner(st, r)) and not CSea.spared(st, f, r):
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
		if CAI.needed_home(st, f, a, cx):
			CP.count(CP.C_FERRY_REFUSED, f)
			continue
		out.append(a)
	return out


## (Garrisons against landings) Fleet fl may ferry troops past the cells
## `route` (where it is, where it embarks or lands, the way between): each
## fleet at war with f that reaches one of them this turn (straight line at its
## pace) has at most 100 / FERRY_ODDS_PCT times fl's power, summed over the
## fleets near the same cell (the sea-battle odds: the rolls of
## CFleet.resolve are ROLL_MIN .. ROLL_MIN + ROLL_SPAN %). Off at 0 (Easy).
static func _ferry_safe(st: Dictionary, f: int, fl: Dictionary, route: Array) -> bool:
	var pct := CP.of(st, f)[CP.FERRY_ODDS_PCT]
	if pct <= 0:
		return true
	var mine := _power(fl)
	for c in route:
		if int(c) < 0:
			continue
		var foe := 0
		for e in CFleet.fleets(st):
			if not CState.at_war(st, f, int(e["f"])) or (e["ships"] as Array).is_empty() or CSea.is_flota(e):
				continue
			if CGrid.octile(CFleet.cell(e), int(c)) <= maxi(CFleet.speed(e), 1):
				foe += _power(e)
		if mine * 100 < foe * pct:
			return false
	return true


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
				or not CState.siege_at(st, t).is_empty() or CSea.spared(st, f, t) or CAI._shield(st, f, t):
			continue
		var tt := _turns(fl, b)
		if tt > MAX_TURNS or not _approach(st, fl, b) or _storm_at(st, b):
			continue
		if not _ferry_safe(st, f, fl, [b, _mid(CFleet.cell(fl), b)]):
			continue
		var d := maxi(CAI.target_defence(st, f, t), 1)
		# The formula's chance of the troops against the AI's defence estimate
		# (docs/AI.md 12.1): at least the level's attack threshold.
		if int(CAI.CBattle.odds_of(s, d)["win"]) < CAI._thr(st, CP.of(st, f), CP.ATTACK_WIN):
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
				or not _approach(st, fl, b) or _storm_at(st, b) or not _ferry_safe(st, f, fl, [b, _mid(CFleet.cell(fl), b)]):
			continue
		var d := CGrid.octile(CFleet.cell(fl), b)
		if d < bd:
			bd = d
			home = b
	return home


## The cell halfway between cells a and b (straight line).
static func _mid(a: int, b: int) -> int:
	return CGrid.at((CGrid.cx(a) + CGrid.cx(b)) / 2, (CGrid.cy(a) + CGrid.cy(b)) / 2)


# ---------------------------------------------------------------- fights ---

## An enemy fleet at war fl reaches this turn and beats by ATTACK_PCT (the
## weakest such, ties by id), -1 none. N2: the flota (treasure first) within
## FLOTA_TURNS for pirates (2 for nations) at FLOTA_PCT / PIRATE_FLOTA_PCT;
## pirate fleets at ATTACK_PCT less half their infamy (at least 100), within
## a turn more from infamy 40; pirates attack at PIRATE_ATTACK_PCT.
## treasure_only: the flota alone (before the transports take the fleets).
static func _prey(st: Dictionary, f: int, fl: Dictionary, treasure_only: bool = false) -> int:
	var mine := _power(fl)
	var pir := CSea.pirate(f)
	var best := -1
	var bp := 1 << 30
	var bg := 0
	for e in CFleet.fleets(st):
		if not CState.at_war(st, f, int(e["f"])) or CFleet.docked(e) >= 0:
			continue  # (Docking: a fleet behind the mole is out of reach)
		var ep := _power(e)
		var pct := PIRATE_ATTACK_PCT if pir else ATTACK_PCT
		var horizon := 0
		var g := CSea.treasure(e)
		if treasure_only and g <= 0:
			continue
		if g > 0:
			pct = PIRATE_FLOTA_PCT if pir else FLOTA_PCT
			horizon = FLOTA_TURNS if pir else 2
		elif CSea.pirate(int(e["f"])):
			var inf := CSea.infamy(st, int(e["f"]))
			pct = maxi(pct - inf / 2, 100)
			horizon = 1 if inf >= 40 else 0
		if _turns(fl, CFleet.cell(e)) > horizon or mine * 100 < ep * pct or _storm_at(st, CFleet.cell(e)):
			continue
		if mine * 100 < _defence_at(st, e) * pct:
			continue  # (its friends and its port's guns beside it)
		if CFleet.coastal(fl) and not CFleet.coastal_link(CFleet.cell(fl), CFleet.cell(e)):
			continue
		if g > bg or (g == bg and ep < bp):
			bg = g
			bp = ep
			best = int(e["id"])
	return best


## (Sorties, docs/AI.md 12.4) For each port (region order) where fleets of
## ours in `mine` lie docked: the strongest of them (lowest id on ties) that
## is empty, free (not used this act, not in a pending battle) and in good
## repair (BLOCKADE_HULL) sorties against an enemy fleet at war within
## BLOCKADE_CELLS + SORTIE_REACH of the harbour that is not docked nor busy,
## out of the storms' cones, that it reaches this turn: a fleet lying off the
## port (within BLOCKADE_CELLS: the blockade's ground, whether or not it holds
## the blockade) at SORTIE_ODDS_PCT of the enemy's power at the spot
## (_sortie_foe), one merely passing (beyond) at SORTIE_HUNT_PCT (0: never).
## The port's blockader (CSea.blockader) first, then the others lying off it,
## then the passing; the weakest enemy at the spot, then the lowest id. An
## fmove after it (tgt), counted C_SORTIES.
static func _sorties(st: Dictionary, f: int, mine: Array, used: Dictionary, fmoves: Array) -> void:
	var kn := CP.of(st, f)
	var odds := kn[CP.SORTIE_ODDS_PCT]
	var hunt := kn[CP.SORTIE_HUNT_PCT]
	if odds <= 0 and hunt <= 0:
		return
	var rad := CSea.k("BLOCKADE_CELLS", 3)
	var reach := rad + kn[CP.SORTIE_REACH]
	for r in CData.region_count():
		var hb := CFleet.harbour(r)
		if hb < 0:
			continue
		var fl := {}
		for x in mine:
			if CFleet.docked(x) != r or used.has(int(x["id"])) or x.has("busy") or not (x["carry"] as Array).is_empty() \
					or _hull(x) < BLOCKADE_HULL:
				continue
			if fl.is_empty() or _power(x) > _power(fl):
				fl = x
		if fl.is_empty():
			continue
		var mine_p := _power(fl)
		var bk := CSea.blockader(st, r)
		var best := -1
		var b_rank := -1
		var b_foe := 0
		for e in CFleet.fleets(st):
			if not CState.at_war(st, f, int(e["f"])) or (e["ships"] as Array).is_empty() or CFleet.docked(e) >= 0 \
					or e.has("busy"):
				continue
			var d := CGrid.cheb(CFleet.cell(e), hb)
			if d > reach:
				continue
			# rank 2: the port's blockader lying off it; 1: another lying off it; 0: passing
			var rank := 0 if d > rad else (2 if int(e["f"]) == bk else 1)
			var pct := odds if rank > 0 else hunt
			if pct <= 0 or rank < b_rank:
				continue
			if _storm_at(st, CFleet.cell(e)) or _turns(fl, CFleet.cell(e)) > 0:
				continue
			if CFleet.coastal(fl) and not CFleet.coastal_link(CFleet.cell(fl), CFleet.cell(e)):
				continue
			var foe := _sortie_foe(st, f, e)
			if mine_p * 100 < foe * pct:
				continue
			if rank > b_rank or foe < b_foe:
				best = int(e["id"])
				b_rank = rank
				b_foe = foe
		if best < 0:
			continue
		used[int(fl["id"])] = 1
		fl.erase("job")
		fmoves.append([int(fl["id"]), -1, f, 0, best])
		CP.count(CP.C_SORTIES, f)


## (Sorties) The enemy's power a sortie against fleet e meets: the fleets at
## war with f within FLEET_ZONE + 1 of it (CFleet.sea_battle gathers every
## fleet in the zone; not docked, not busy), times its port's guns when e
## lies in a port of its own (CFleet.resolve's defender bonus; the sortie is
## the attacker, which has none).
static func _sortie_foe(st: Dictionary, f: int, e: Dictionary) -> int:
	var p := 0
	var c := CFleet.cell(e)
	for x in CFleet.fleets(st):
		if CState.at_war(st, f, int(x["f"])) and CFleet.docked(x) < 0 and not x.has("busy") \
				and CGrid.cheb(CFleet.cell(x), c) <= CFleet.FLEET_ZONE + 1:
			p += _power(x)
	var r := CFleet.port_of(st, e, int(e["f"]))
	if r >= 0:
		p = p * (CFleet.PORT_DEF_PCT + CFleet.PORT_WALL_PCT * CState.walls(st, r)) / 100
	return p


## (N2) Where fleet fl lies in wait for fleet e on its course (e's route,
## the cells it has yet to sail): the first cell of it beyond what e sails
## in a turn that fl reaches this turn, else the cell two turns of e's sail
## ahead; -1 when e has no route (then fl chases it).
static func _intercept(st: Dictionary, fl: Dictionary, e: Dictionary) -> int:
	var route: Array = e.get("route", [])
	if route.is_empty():
		return -1
	var f := int(fl["f"])
	var pace := maxi(CFleet.speed(e) / 12, 1)  # (cells a turn, about)
	var far := -1
	for i in route.size():
		var c := int(route[i])
		if i + 1 < pace:
			continue
		var reach := _turns(fl, c) == 0
		if not reach and (far >= 0 or i < pace * 2):
			continue
		var zo := CFleet.zone_owner(st, f, c)
		if (zo >= 0 and zo != int(e["id"])) or _near_port(c) or _storm_at(st, c):
			continue  # (not under another enemy's guns, nor in a storm's path)
		if reach:
			return c
		far = c
	return far


## Cell c is within PORT_CELLS + 2 of the harbour of a port at war with
## the acting faction (_hostile_hb, this act's).
static func _near_port(c: int) -> bool:
	for hb in _hostile_hb:
		if CGrid.cheb(hb, c) <= CFleet.PORT_CELLS + 2:
			return true
	return false


## Power that would meet an attack on fleet e: the fleets of its side
## within FLEET_ZONE + 1 of it, times its port's guns (CFleet's defender
## bonus) when it lies in its own port.
static func _defence_at(st: Dictionary, e: Dictionary) -> int:
	var p := 0
	var c := CFleet.cell(e)
	for x in CFleet.fleets(st):
		if CGrid.cheb(CFleet.cell(x), c) <= CFleet.FLEET_ZONE + 1 and CState.friendly(st, int(x["f"]), int(e["f"])):
			p += _power(x)
	var r := CFleet.port_of(st, e, int(e["f"]))
	if r >= 0:
		p = p * (CFleet.PORT_DEF_PCT + CFleet.PORT_WALL_PCT * CState.walls(st, r)) / 100
	return p


## (N2) A port for fleet fl of faction f to blockade: [region, station
## cell] or []. Keeps the station it holds (within BLOCKADE_CELLS of an
## enemy harbour, its guard outgunned); else the enemy port at war with the
## most sea trade per estimated turn (at most BLOCKADE_TURNS), not taken by
## another fleet of ours this turn, whose guard (fleets of its side within
## GUARD_CELLS) we outgun by SAFE_PCT; the station is the free sea cell on
## its approach nearest us (outside enemy zones; ties by cell index).
static func _blockade(st: Dictionary, f: int, fl: Dictionary, taken: Dictionary) -> Array:
	var mine := _power(fl)
	var rad := CSea.k("BLOCKADE_CELLS", 3)
	var here := CFleet.cell(fl)
	var best := -1
	var bv := -1
	for r in CData.region_count():
		var hb := CFleet.harbour(r)
		var o := CState.owner(st, r)
		if hb < 0 or o < 0 or taken.has(r) or not CState.at_war(st, f, o) or _storm_at(st, hb) or CAI._shield(st, f, r):
			continue
		var trade := CSea.sea_trade(st, r)
		var sieged := CP.skill(st, f) == CP.SKILLED and int(CState.siege_at(st, r).get("f", -1)) == f  # (lanes) Skilled: our siege
		if trade <= 0 and not sieged:
			continue
		if not _gd.has(r):
			_gd[r] = _guard(st, o, hb)
		if int(_gd[r]) * SAFE_PCT > mine * 100:
			continue
		if CGrid.cheb(here, hb) <= rad and CFleet.zone_owner(st, f, here) < 0:
			return [r, here]  # we hold it
		var tt := _turns(fl, hb)
		if tt > BLOCKADE_TURNS + (2 if sieged else 0):
			continue
		var v := maxi(trade, 1) * 100 / (1 + tt) * (3 if sieged else 1)
		if v > bv:
			bv = v
			best = r
	if best < 0:
		return []
	var hb2 := CFleet.harbour(best)
	var lim := int(CData.ship_const("COASTAL_CELLS", 2))
	var rg := int(fl.get("rgoal", -1))
	if rg >= 0 and CFleet.is_sea(rg) and CGrid.cheb(rg, hb2) <= rad and CFleet.zone_owner(st, f, rg) < 0 \
			and not (CFleet.coastal(fl) and (CFleet.coast_dist(rg) > lim or not CFleet.coastal_link(here, rg))):
		return [best, rg]  # (the station it was sailing for: its route is kept)
	var sc := CSea.blockade_station(st, f, fl, best)
	return [best, sc] if sc >= 0 else []


## The power of the fleets of the factions at war with f (the flota and
## empty fleets count for nothing).
static func _foe_power(st: Dictionary, f: int) -> int:
	var n := 0
	for e in CFleet.fleets(st):
		if CState.at_war(st, f, int(e["f"])) and not CSea.is_flota(e) and not (e["ships"] as Array).is_empty():
			n += _power(e)
	return n


## (lanes) The lane fleet fl should raid: [lane id, station cell] or [].
## Keeps the lane it lies on; else the enemy lane worth most per estimated
## turn to reach (at most RAID_TURNS) not raided by us already (`taken`: lane
## ids this act, `rt`: CLanes.raiders), its station a free cell on the lane
## (outside enemy zones, out of the storms' cones). Nothing with an enemy
## fleet at war within RAID_FLEE_CELLS.
static func _raid(st: Dictionary, f: int, fl: Dictionary, taken: Dictionary, rt: Dictionary) -> Array:
	var here := CFleet.cell(fl)
	for e in CFleet.fleets(st):
		if CState.at_war(st, f, int(e["f"])) and not (e["ships"] as Array).is_empty() \
				and CGrid.cheb(CFleet.cell(e), here) <= RAID_FLEE_CELLS:
			return []
	var best := -1
	var bv := 0
	var bs := -1
	for id in CLanes.lanes_at(here):  # (the lane it lies on first)
		if int(id) < CLanes.count() and not taken.has(id) and CLanes.hostile(st, f, int(id)) \
				and (not rt.has(id) or int((rt[id] as Dictionary)["id"]) == int(fl["id"])) and _lane_gold(st, f, int(id)) > 0:
			return [int(id), here]
	for id in CLanes.count():
		if taken.has(id) or not CLanes.hostile(st, f, id):
			continue
		if rt.has(id) and int((rt[id] as Dictionary)["id"]) != int(fl["id"]):
			continue  # somebody holds it already
		var v := _lane_gold(st, f, id)
		if v <= 0:
			continue
		var stn := CLanes.raid_station(st, f, fl, id)
		if stn < 0 or CFleet.zone_owner(st, f, stn) >= 0 or _storm_at(st, stn):
			continue
		if stn == here:
			return [id, here]  # we hold it
		var tt := _turns(fl, stn)
		if tt > RAID_TURNS:
			continue
		var sc := v * 100 / (1 + tt)
		if sc > bv:
			bv = sc
			best = id
			bs = stn
	return [best, bs] if best >= 0 else []


## What lane id pays now to the ports of its owners at war with f.
static func _lane_gold(st: Dictionary, f: int, id: int) -> int:
	var ls := CLanes.lane_state(st, id, {})
	var v := 0
	if int(ls["oa"]) >= 0 and CState.at_war(st, f, int(ls["oa"])):
		v += int(ls["pa"])
	if int(ls["ob"]) >= 0 and CState.at_war(st, f, int(ls["ob"])):
		v += int(ls["pb"])
	return v


## Power of the fleets on faction o's side within GUARD_CELLS of cell hb.
static func _guard(st: Dictionary, o: int, hb: int) -> int:
	var p := 0
	for e in CFleet.fleets(st):
		if CGrid.cheb(CFleet.cell(e), hb) <= GUARD_CELLS and CState.friendly(st, o, int(e["f"])):
			p += _power(e)
	return p


static func _hull(fl: Dictionary) -> int:
	var n := 0
	var h := 0
	for s in fl["ships"]:
		h += int(s["h"])
		n += 1
	return h / maxi(n, 1)


static func _danger(st: Dictionary, f: int, fl: Dictionary) -> bool:
	var mine := _power(fl)
	var pct := PIRATE_DANGER_PCT if CSea.pirate(f) else DANGER_PCT
	for e in CFleet.fleets(st):
		if CState.at_war(st, f, int(e["f"])) and _power(e) * 100 > mine * pct \
				and CGrid.cheb(CFleet.cell(e), CFleet.cell(fl)) <= DANGER_CELLS:
			return true
	return false


## The dock of our port nearest fleet fl (straight line), -1 none; (N2b)
## one out of the storms' cones first.
static func _home(st: Dictionary, f: int, fl: Dictionary) -> int:
	var h := _home_any(st, f, fl, true)
	return h if h >= 0 or not _stormy else _home_any(st, f, fl, false)


static func _home_any(st: Dictionary, f: int, fl: Dictionary, safe: bool) -> int:
	var best := -1
	var bd := 1 << 30
	for r in CData.region_count():
		var o := CState.owner(st, r)
		if o != f and not (CSea.pirate(f) and o >= 0 and CSea.has_marque(st, f, o)):
			continue  # (N2: privateers put in at their patron's ports)
		var dk := CFleet.dock(r)
		if dk < 0 or CFleet.zone_owner(st, f, dk) >= 0 or (CFleet.coastal(fl) and not CFleet.coastal_link(CFleet.cell(fl), dk)):
			continue
		if safe and _storm_at(st, dk):
			continue
		var d := CGrid.octile(CFleet.cell(fl), dk)
		if d < bd:
			bd = d
			best = dk
	return best


## (N2b) Where fleet fl runs from a storm: a dock of ours (or a patron's)
## out of every cone that it reaches this turn (straight line), else the
## clear sea cell nearest it within SHELTER_CELLS out of every cone and
## enemy zone (ties by cell index), -1 none.
const SHELTER_CELLS := 16


static func _shelter(st: Dictionary, f: int, fl: Dictionary) -> int:
	var h := _home_any(st, f, fl, true)
	if h >= 0 and _turns(fl, h) == 0:
		return h
	var here := CFleet.cell(fl)
	var lim := int(CData.ship_const("COASTAL_CELLS", 2))
	var coast := CFleet.coastal(fl)
	var best := -1
	var bd := 1 << 30
	for j in CGrid.disc(here, SHELTER_CELLS):
		if not CFleet.is_sea(j) or CFleet.zone_owner(st, f, j) >= 0 or CStorm.danger(st, j, 1):
			continue
		if coast and (CFleet.coast_dist(j) > lim or not CFleet.coastal_link(here, j)):
			continue
		var d := CGrid.octile(here, j)
		if d < bd or (d == bd and j < best):
			bd = d
			best = j
	return best
