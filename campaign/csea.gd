extends RefCounted
## Trade at sea, blockades, the flota and the pirate loop (N2, a pack with
## ships: CFleet.on(st); docs/CAMPAIGN.md "Trade, blockades, the flota and
## pirates (N2)"; the numbers are the pack's ships script, e.g.
## campaign/data/west_ships.gd). Same discipline as the rest of campaign/:
## integers, the state's RNG, arrays in index order, no Nodes. A Rome state
## never reaches any of this (no "fleets" key): every hook checks on(st).
##
## State (only in a pack with ships; every key optional, read with defaults):
##   regions[r]: "bk" the faction blockading its port (set at the end of a
##     turn, read by income and the view), "sacked" the turn it was last
##     sacked;
##   factions[f]: "plunder" (gold taken in all: prizes, blockades, the
##     flota, sacks), "infamy" (pirates), "sack_pol" (pirates: 0 auto, 1
##     sack, 2 hold);
##   fleets[i]: "flota" (its leg: 0 to the meeting port, 1 waiting there,
##     2 home), "wait" (turns waited); ships [{..., "g": treasure, "o":
##     faction it pays}];
##   marques [[nation, pirate, until turn], ...] (letters of marque);
##   (N2b) flota ships "nm" (the galleon's name), "cap" (1: the capitana);
##   fleets "held" (the flota waiting out a storm); wrecks [[x, y, turn,
##   gold, name], ...] (treasure ships sunk, the last WRECKS_MAX);
##   stats: plunder, blockade_turns, flotas, flota_arrived, flota_gold,
##     treasure_taken, sacks, marques, lane_raids, lane_raid_gold;
##   (lanes, 2026-10-22) flota fleets "ln" (the lane id they follow);
## The lanes' trade, raids and the station orders: campaign/clanes.gd
## (state functions) and the "Sea lanes" section below.
## Orders (crules.apply_order): sack_policy {v}; propose {to, what:
## "marque"} (a nation to a pirate faction or back); (lanes) fraid {fleet,
## lane}, fblockade {fleet, r}: sail to a station and hold it (stored voyages);
## (Docking) fdock {fleet, r}: sail to a port's dock and dock there.

const CData := preload("res://campaign/cdata.gd")
const CState := preload("res://campaign/cstate.gd")
const CGrid := preload("res://campaign/cgrid.gd")
const CFleet := preload("res://campaign/cfleet.gd")
const CStorm := preload("res://campaign/cstorm.gd")
const CCaptain := preload("res://campaign/ccaptain.gd")
const CLanes := preload("res://campaign/clanes.gd")
const UT := preload("res://sim/unit_types.gd")


static func _rules() -> GDScript:
	return load("res://campaign/crules.gd")


static func on(st: Dictionary) -> bool:
	return st.has("fleets")


static func k(key: String, default: int) -> int:
	return int(CData.ship_const(key, default))


static func _stat(st: Dictionary, key: String, n: int) -> void:
	var s: Dictionary = st["stats"]
	s[key] = int(s.get(key, 0)) + n


# --------------------------------------------------------------- pirates ---

## Faction f is a pirate faction (the pack's "pirate" flag).
static func pirate(f: int) -> bool:
	return f >= 0 and f < CData.FACTIONS.size() and int(CData.FACTIONS[f].get("pirate", 0)) != 0


static func infamy(st: Dictionary, f: int) -> int:
	if f < 0 or f >= CState.nf():
		return 0
	return int(st["factions"][f].get("infamy", 0))


static func add_infamy(st: Dictionary, f: int, n: int) -> void:
	if not pirate(f) or n == 0:
		return
	st["factions"][f]["infamy"] = clampi(infamy(st, f) + n, 0, k("INFAMY_MAX", 100))


## A pirate faction with a ship afloat (it lives on without a region).
static func afloat(st: Dictionary, f: int) -> bool:
	if not on(st) or not pirate(f):
		return false
	for fl in CFleet.fleets_of(st, f):
		if not (fl["ships"] as Array).is_empty():
			return true
	return false


## Region r is a pirate haven: a port held by a pirate faction.
static func haven(st: Dictionary, r: int) -> bool:
	return on(st) and pirate(CState.owner(st, r)) and CFleet.harbour(r) >= 0


## Percent off the price of unit `key` for faction f recruiting in r (a
## haven's crews; 0 elsewhere).
static func haven_off(st: Dictionary, f: int, r: int, key: String) -> int:
	if not haven(st, r) or CState.owner(st, r) != f:
		return 0
	if not (CData.ship_const("HAVEN_UNITS", []) as Array).has(key):
		return 0
	# (N2b) a famous captain draws crews cheaper still.
	return mini(k("HAVEN_PCT", 20) + infamy(st, f) / 5, k("HAVEN_MAX_PCT", 45)) \
		+ k("CAPT_HAVEN_PCT", 0) * CCaptain.tier(CCaptain.best_fame(st, f))


## More recruits a turn in region r (a haven, by its owner's infamy).
static func extra_recruits(st: Dictionary, r: int) -> int:
	if not haven(st, r):
		return 0
	var o := CState.owner(st, r)
	var legend := 1 if CCaptain.tier(CCaptain.best_fame(st, o)) >= 3 else 0  # (N2b) a Legend's name brings recruits
	return mini(infamy(st, o) / maxi(k("HAVEN_RECRUIT_INFAMY", 30), 1), 2) + legend


## % of plunder pirate faction p takes from `victim` (a letter of marque
## from a nation at war with the victim adds MARQUE_BONUS_PCT).
static func plunder_pct(st: Dictionary, p: int, victim: int) -> int:
	if not pirate(p) or victim < 0:
		return 100
	for m in marques(st):
		if int(m[1]) == p and CState.at_war(st, int(m[0]), victim):
			return 100 + k("MARQUE_BONUS_PCT", 50)
	return 100


## Faction f takes `gold` of plunder from `victim` (-1: nobody in
## particular; a letter of marque may add to it). Returns what was paid.
static func gain(st: Dictionary, f: int, gold: int, victim: int = -1) -> int:
	if f < 0 or gold <= 0:
		return 0
	var g := gold * plunder_pct(st, f, victim) / 100
	var fs: Dictionary = st["factions"][f]
	fs["treasury"] = int(fs["treasury"]) + g
	fs["plunder"] = int(fs.get("plunder", 0)) + g
	_stat(st, "plunder", g)
	return g


# -------------------------------------------------------- trade, blockade ---

## Region r's trade by sea a turn (0 inland).
static func sea_trade(st: Dictionary, r: int) -> int:
	if CFleet.harbour(r) < 0:
		return 0
	return int(CData.REGIONS[r]["wealth"]) * CData.WEALTH_INCOME * k("SEA_TRADE_PCT", 60) / 100 \
		+ CState.building(st, r, CData.MARKET) * CData.MARKET_INCOME


## The faction blockading region r's port (-1 none; as of the last turn's end).
static func blockader(st: Dictionary, r: int) -> int:
	var rg: Array = st["regions"]
	return int(rg[r].get("bk", -1)) if r >= 0 and r < rg.size() else -1   # (a state of another pack: none)


## What region r's owner loses a turn to its blockade.
static func blockade_loss(st: Dictionary, r: int) -> int:
	if blockader(st, r) < 0 or not CState.siege_at(st, r).is_empty():
		return 0
	return sea_trade(st, r) * k("BLOCKADE_CUT_PCT", 75) / 100


## What the blockader of region r takes a turn.
static func blockade_take(st: Dictionary, r: int) -> int:
	var b := blockader(st, r)
	if b < 0:
		return 0
	var pct := k("PIRATE_TAKE_PCT", 80) if pirate(b) else k("BLOCKADE_TAKE_PCT", 40)
	return blockade_loss(st, r) * pct / 100 * plunder_pct(st, b, CState.owner(st, r)) / 100


## Faction f's blockade terms for income(): [lost by its blockaded ports,
## taken from the ports it blockades, regions it blockades].
static func income_parts(st: Dictionary, f: int) -> Array:
	var lost := 0
	var take := 0
	var n := 0
	for r in CData.region_count():
		var b := blockader(st, r)
		if b < 0:
			continue
		if CState.owner(st, r) == f:
			lost += blockade_loss(st, r)
		if b == f:
			take += blockade_take(st, r)
			n += 1
	return [lost, take, n]


## The fleets' powers near region r's harbour: the strongest faction at war
## with the owner [faction, power] and the owner's side's power. `pw`:
## fleet index in st.fleets -> power (-1: the flota or no ships).
static func _blockade_sides(st: Dictionary, r: int, pw: PackedInt32Array) -> Array:
	var o := CState.owner(st, r)
	var hb := CFleet.harbour(r)
	var rad := k("BLOCKADE_CELLS", 3)
	var per: Array[int] = []
	per.resize(CState.nf())
	per.fill(0)
	var own := 0
	var fls := CFleet.fleets(st)
	for i in fls.size():
		var fl: Dictionary = fls[i]
		if pw[i] < 0 or CGrid.cheb(CFleet.cell(fl), hb) > rad:
			continue
		var g := int(fl["f"])
		if CState.friendly(st, g, o):
			own += pw[i]
		elif CState.at_war(st, g, o):
			per[g] += pw[i]
	var best := -1
	for g in CState.nf():
		if per[g] > 0 and (best < 0 or per[g] > per[best]):
			best = g
	return [best, per[best] if best >= 0 else 0, own]


## End of turn, before the money: every port's blockade from where the
## fleets lie now (an enemy at war within BLOCKADE_CELLS of the harbour,
## stronger there than the owner's side). Events "blockade" (a new one) and
## "blockade_end".
static func update_blockades(st: Dictionary) -> void:
	var pw := PackedInt32Array()
	for fl in CFleet.fleets(st):
		pw.append(-1 if fl.has("flota") or (fl["ships"] as Array).is_empty() else CFleet.power(fl))
	for r in CData.region_count():
		var rs: Dictionary = st["regions"][r]
		var old := int(rs.get("bk", -1))
		var b := -1
		var o := int(rs["owner"])
		if o >= 0 and CFleet.harbour(r) >= 0:
			var sd := _blockade_sides(st, r, pw)
			if int(sd[0]) >= 0 and int(sd[1]) > int(sd[2]):
				b = int(sd[0])
		if b >= 0:
			rs["bk"] = b
			_stat(st, "blockade_turns", 1)
			add_infamy(st, b, 1)
			if b != old:
				_rules().event(st, {"k": "blockade", "r": r, "f": b, "from": o})
		elif old >= 0:
			rs.erase("bk")
			_rules().event(st, {"k": "blockade_end", "r": r, "f": old, "from": o})


# -------------------------------------------------------------- sea lanes ---

## A raider's prize money (`gold`, already in the treasury through income())
## counts as plunder (the stories' chests), and its owner's infamy grows.
static func lane_plunder(st: Dictionary, f: int, gold: int) -> void:
	if f < 0 or gold <= 0:
		return
	var fs: Dictionary = st["factions"][f]
	fs["plunder"] = int(fs.get("plunder", 0)) + gold
	_stat(st, "plunder", gold)
	_stat(st, "lane_raid_gold", gold)


## End of turn, before the money: every raided lane is told in the chronicle
## (event "lane_raided": f the raider's faction, from / to the end owners,
## lane, ra / rb the end regions, gold the cut, take the raider's share, x / y
## the raider's cell: seen by the owners, else by whoever sees that cell) and
## a pirate raider's infamy grows.
static func lane_events(st: Dictionary) -> void:
	if CData.SEA_LANES.is_empty():
		return
	var rt := CLanes.raiders(st)
	for id in CLanes.count():
		if not rt.has(id):
			continue
		var ls := CLanes.lane_state(st, id, rt)
		var cut := int(ls["cuta"]) + int(ls["cutb"])
		if cut <= 0:
			continue
		var e := CLanes.ends(id)
		_stat(st, "lane_raids", 1)
		add_infamy(st, int(ls["rf"]), 1)
		var rc := CFleet.cell(CFleet.fleet(st, int(ls["rid"])))
		_rules().event(st, {"k": "lane_raided", "f": int(ls["rf"]), "from": int(ls["oa"]), "to": int(ls["ob"]), "lane": id,
			"ra": int(e[0]), "rb": int(e[1]), "gold": cut, "take": int(ls["take"]), "x": CGrid.cx(rc), "y": CGrid.cy(rc)})


## "" if the station order o (fraid {fleet, lane} or fblockade {fleet, r})
## of faction f is valid now, else why not. Nothing changes: the order is a
## voyage to the station, planned and sailed with the fleets' moves (cturn).
static func station_check(st: Dictionary, f: int, o: Dictionary) -> String:
	return str(station_plan(st, f, o).get("why", ""))


## The station order's plan: {dest (the cell to sail to; the fleet's own when
## it is there already)} or {why}.
static func station_plan(st: Dictionary, f: int, o: Dictionary) -> Dictionary:
	var fl := CFleet.fleet(st, int(o.get("fleet", -1)))
	if fl.is_empty() or int(fl["f"]) != f:
		return {"why": "no such fleet"}
	if (fl["ships"] as Array).is_empty():
		return {"why": "no ships"}
	if fl.has("sto") or fl.has("flota"):
		return {"why": "sails by the story" if fl.has("sto") else "the flota sails by the Crown's orders"}
	if fl.has("busy"):
		return {"why": "in a sea battle"}
	var dest := -1
	if str(o.get("t", "")) == "fdock":
		var dr := int(o.get("r", -1))
		if dr < 0 or dr >= CData.region_count() or CFleet.dock(dr) < 0:
			return {"why": "no dock there"}
		if not CFleet.can_dock(st, f, dr):
			return {"why": "not a port of ours or a friend's"}
		dest = CFleet.dock(dr)
	elif str(o.get("t", "")) == "fraid":
		var id := int(o.get("lane", -1))
		if id < 0 or id >= CLanes.total():
			return {"why": "no lane here"}
		if not CLanes.hostile(st, f, id):
			return {"why": "not at war with this lane's ports"}
		dest = CLanes.raid_station(st, f, fl, id)
		if dest < 0:
			return {"why": "no way to this lane by sea"}
	else:
		var r := int(o.get("r", -1))
		if r < 0 or r >= CData.region_count() or CFleet.harbour(r) < 0:
			return {"why": "no harbour there"}
		var ow := CState.owner(st, r)
		if ow < 0 or not CState.at_war(st, f, ow):
			return {"why": "not at war with the port's owner"}
		dest = blockade_station(st, f, fl, r)
		if dest < 0:
			return {"why": "no station off this harbour"}
	if dest != CFleet.cell(fl):
		var why := CFleet.move_check(st, f, int(fl["id"]), dest)
		if why != "":
			return {"why": why}
	return {"dest": dest}


## The sea cell fleet fl of faction f lies on to blockade region r's port: its
## own cell when it is within BLOCKADE_CELLS of the harbour already (outside
## enemy zones), else the free sea cell within that of the harbour nearest it
## (outside enemy zones, a coastal fleet only where it keeps to the coast;
## ties by cell index). -1 none.
static func blockade_station(st: Dictionary, f: int, fl: Dictionary, r: int) -> int:
	var hb := CFleet.harbour(r)
	if hb < 0:
		return -1
	var rad := k("BLOCKADE_CELLS", 3)
	var here := CFleet.cell(fl)
	if CGrid.cheb(here, hb) <= rad and CFleet.zone_owner(st, f, here) < 0:
		return here
	var lim := int(CData.ship_const("COASTAL_CELLS", 2))
	var sc := -1
	var sd := 1 << 30
	for dy in range(-rad, rad + 1):
		for dx in range(-rad, rad + 1):
			var j := CGrid.at(CGrid.cx(hb) + dx, CGrid.cy(hb) + dy)
			if j < 0 or not CFleet.is_sea(j) or CFleet.zone_owner(st, f, j) >= 0:
				continue
			if CFleet.coastal(fl) and (CFleet.coast_dist(j) > lim or not CFleet.coastal_link(here, j)):
				continue
			var d := CGrid.octile(here, j)
			if d < sd or (d == sd and j < sc):
				sd = d
				sc = j
	return sc


# ------------------------------------------------------------------ flota ---

static func is_flota(fl: Dictionary) -> bool:
	return fl.has("flota")


## The first turn the next flota gathers for (> the current turn).
static func next_flota(st: Dictionary) -> int:
	var first := k("FLOTA_FIRST", 4)
	var every := maxi(k("FLOTA_EVERY", 8), 1)
	var t := int(st["turn"]) + 1
	if t <= first:
		return first
	return first + ((t - first + every - 1) / every) * every


## The flota's owner (FLOTA_OWNER, else the first part's faction alive; -1 none).
static func flota_owner(st: Dictionary) -> int:
	var o := CData.faction_index(str(CData.ship_const("FLOTA_OWNER", "")))
	if o >= 0 and CState.alive(st, o):
		return o
	for p in CData.ship_const("FLOTA_PARTS", []):
		var f := CData.faction_index(str(p[1]))
		if f >= 0 and CState.alive(st, f):
			return f
	return -1


## The sea cell where the flota leaves the map (-1 none).
static func exit_cell() -> int:
	# (lanes) the end of the meeting port's exit lane when the pack has one (the flota follows it home)
	var xl := CLanes.exit_of(CData.region_index(str(CData.ship_const("FLOTA_MEET", ""))))
	if xl >= 0:
		var lc := CLanes.sea_cells(xl)
		if not lc.is_empty():
			return lc[lc.size() - 1]
	var e: Array = CData.ship_const("FLOTA_EXIT", [])
	if e.size() < 2:
		return -1
	var c := CGrid.at(int(e[0]), int(e[1]))
	return c if CFleet.is_sea(c) else -1


## The meeting port's dock (-1 none).
static func meet_cell() -> int:
	var r := CData.region_index(str(CData.ship_const("FLOTA_MEET", "")))
	return CFleet.dock(r) if r >= 0 else -1


## End of turn: when the next turn is a flota turn, its galleons gather in
## the docks of the parts' origins (event "flota", in the chronicle).
static func flota_spawn(st: Dictionary) -> void:
	var parts: Array = CData.ship_const("FLOTA_PARTS", [])
	if parts.is_empty() or exit_cell() < 0:
		return
	var t := int(st["turn"]) + 1
	var first := k("FLOTA_FIRST", 4)
	if t < first or (t - first) % maxi(k("FLOTA_EVERY", 8), 1) != 0:
		return
	var fo := flota_owner(st)
	if fo < 0:
		return
	var made: Array = []
	# (N2b) The Crown adds escorts when the pirates afloat are infamous.
	var escorts := 0
	var worst := 0
	for g in CState.nf():
		if pirate(g) and CState.alive(st, g):
			worst = maxi(worst, infamy(st, g))
	for v in CData.ship_const("ESCORT_INFAMY", []):
		if worst >= int(v):
			escorts += 1
	var capitana := false
	var taken_names: Array = []
	for p in parts:
		var r := CData.region_index(str(p[0]))
		var pf := CData.faction_index(str(p[1]))
		if r < 0 or CFleet.dock(r) < 0:
			continue
		var o := CState.owner(st, r)
		if o < 0 or (o != pf and o != fo) or not CState.siege_at(st, r).is_empty():
			continue
		var pay := pf if pf >= 0 and CState.alive(st, pf) else fo
		var ships: Array = []
		var n := 0
		var names: Array = []
		for key in p[2]:
			var row := CData.ship_row(str(key))
			if row.is_empty():
				continue
			if str(key) == "galleon":
				var sh := {"t": str(key), "h": 100, "c": k("FLOTA_CREW", 60), "g": k("FLOTA_GOLD", 900), "o": pay}
				var nm := galleon_name(st, taken_names)
				if nm != "":
					sh["nm"] = nm  # (N2b) named; the first is the capitana with the big chest
					names.append(nm)
					taken_names.append(nm)
					_stat(st, "galleons_named", 1)
				if not capitana and CData.ship_const("FLOTA_CAPITANA_GOLD", null) != null:
					capitana = true
					sh["cap"] = 1
					sh["g"] = k("FLOTA_CAPITANA_GOLD", 1800)
				ships.append(sh)
				n += 1
			else:
				ships.append({"t": str(key), "h": 100, "c": 100})
		if ships.is_empty():
			continue
		for e in escorts:
			if not CData.ship_row("frigate").is_empty():
				ships.append({"t": "frigate", "h": 100, "c": 100})
		var fl := CFleet._new_fleet(st, fo, CFleet.dock(r), ships)
		fl["flota"] = 0
		fl["wait"] = 0
		var ln := CLanes.lane_between(r, CData.region_index(str(CData.ship_const("FLOTA_MEET", ""))))
		if ln >= 0:
			fl["ln"] = ln  # (lanes) it sails to the meeting port along this lane
		made.append([r, n, pay, names, escorts])
	if made.is_empty():
		return
	_stat(st, "flotas", 1)
	_rules().event(st, {"k": "flota", "f": fo, "parts": made, "turn_due": t})


## (N2b) A name for a new treasure galleon: one of GALLEON_NAMES not afloat
## nor in `also` (by the state's RNG), "" when the pack has none.
static func galleon_name(st: Dictionary, also: Array = []) -> String:
	var names: Array = CData.ship_const("GALLEON_NAMES", [])
	if names.is_empty():
		return ""
	var used := {}
	for n in also:
		used[str(n)] = 1
	for fl in CFleet.fleets(st):
		for sh in fl["ships"]:
			if sh.has("nm"):
				used[str(sh["nm"])] = 1
	var free: Array = []
	for n in names:
		if not used.has(str(n)):
			free.append(str(n))
	if free.is_empty():
		return str(names[CState.rand(st, names.size())])
	return str(free[CState.rand(st, free.size())])


## (N2b) A treasure ship sh went down at cell c (why "battle" or "storm";
## by: the faction that sank her, -1 none): her treasure is lost and a
## wreck marks the spot (the last WRECKS_MAX kept). Event "galleon_lost"
## (chronicle).
static func wreck(st: Dictionary, sh: Dictionary, c: int, why: String, by: int) -> void:
	var g := int(sh.get("g", 0))
	if not st.has("wrecks"):
		st["wrecks"] = []
	var wr: Array = st["wrecks"]
	wr.append([CGrid.cx(c), CGrid.cy(c), int(st["turn"]), g, str(sh.get("nm", ""))])
	while wr.size() > k("WRECKS_MAX", 12):
		wr.remove_at(0)
	_stat(st, "galleons_lost", 1)
	_stat(st, "treasure_sunk", g)
	_rules().event(st, {"k": "galleon_lost", "nm": str(sh.get("nm", "")), "g": g, "why": why, "by": by,
		"f": int(sh.get("o", -1)), "x": CGrid.cx(c), "y": CGrid.cy(c)})


## Treasure aboard fleet fl.
static func treasure(fl: Dictionary) -> int:
	var g := 0
	for s in fl["ships"]:
		g += int(s.get("g", 0))
	return g


## A flota part within this of the meeting dock has come in.
const MEET_CELLS := 6


## The flota's voyages this turn (cturn step 5, with the AI's): [fleet,
## dest, faction, persist 0, tgt -1] appended to `out`. A part sails to the
## meeting dock, waits there up to FLOTA_WAIT turns for the others (they
## join), then sails for the exit. It never steers into an enemy's zone
## (it makes for the nearest clear water instead).
static func flota_moves(st: Dictionary, out: Array) -> void:
	if not on(st):
		return
	var meet := meet_cell()
	var mr := CData.region_index(str(CData.ship_const("FLOTA_MEET", "")))
	var ex := exit_cell()
	var list: Array = []
	for fl in CFleet.fleets(st):
		if is_flota(fl):
			list.append(fl)
	if list.is_empty():
		return
	var meet_ok := meet >= 0 and mr >= 0 and CState.friendly(st, int(list[0]["f"]), CState.owner(st, mr))
	var coming := false
	for fl in list:
		if meet_ok and int(fl["flota"]) == 0 and CGrid.cheb(CFleet.cell(fl), meet) > MEET_CELLS:
			coming = true
	# Parts waiting at the meeting port: join and sail when all are in or
	# waited long enough.
	var waiting: Array = []
	for fl in list:
		var leg := int(fl["flota"])
		if leg == 0 and (not meet_ok or CGrid.cheb(CFleet.cell(fl), meet) <= MEET_CELLS):
			fl["flota"] = 1 if meet_ok else 2
		if int(fl["flota"]) == 1:
			waiting.append(fl)
	# (N2b) The flota waits out a hurricane in the meeting port.
	var held := meet >= 0 and CStorm.threat_course(st, meet, ex)
	if not waiting.is_empty():
		var go := (not coming or int(waiting[0]["wait"]) >= k("FLOTA_WAIT", 2)) and not held
		for fl in waiting:
			if not held:
				fl["wait"] = int(fl["wait"]) + 1
		if go:
			var lead: Dictionary = waiting[0]
			for i in range(1, waiting.size()):
				var o: Dictionary = waiting[i]
				if CGrid.cheb(CFleet.cell(o), CFleet.cell(lead)) <= 2:
					(lead["ships"] as Array).append_array(o["ships"])
					(st["fleets"] as Array).erase(o)
				else:
					o["flota"] = 2
			lead["flota"] = 2
	for fl in CFleet.fleets(st):
		if not is_flota(fl) or int(fl["moved"]) != 0:
			continue
		var leg := int(fl["flota"])
		if held and leg >= 1 and CGrid.cheb(CFleet.cell(fl), meet) <= MEET_CELLS:
			if not fl.has("held"):
				fl["held"] = 1
				_rules().event(st, {"k": "flota_held", "f": int(fl["f"]), "fleet": int(fl["id"]), "r": mr})
			continue  # (N2b) in port till the storm has passed
		fl.erase("held")
		var dest := meet if leg == 0 else (ex if leg == 2 else -1)
		# (lanes) The flota follows its lane's cells (to the meeting port, then out by the exit lane), so a raider
		# lying on the lane meets it.
		var lane := int(fl.get("ln", -1)) if leg == 0 else (CLanes.exit_of(mr) if leg == 2 else -1)
		if dest >= 0 and lane >= 0:
			var route := CLanes.cells_to(lane, mr) if leg == 0 else CLanes.cells_of(lane)
			var ah := CLanes.cell_ahead(route, CFleet.cell(fl), CFleet.speed(fl) / 10 + 2)
			if ah >= 0 and ah != CFleet.cell(fl):
				dest = ah
		if dest >= 0:
			var zo := CFleet.zone_owner(st, int(fl["f"]), dest)
			if zo >= 0 and not (lane >= 0 and CLanes.on_lane(lane, CFleet.cell(CFleet.fleet(st, zo)))):
				dest = _clear_near(st, int(fl["f"]), dest)  # an enemy lies there: as near as is clear
		if dest < 0 or CFleet.cell(fl) == dest:
			continue
		out.append([int(fl["id"]), dest, int(fl["f"]), 0, -1])


## The sea cell nearest c (within 6, ties by index) outside the zones of
## fleets at war with f, -1 none.
static func _clear_near(st: Dictionary, f: int, c: int) -> int:
	var best := -1
	var bd := 1 << 30
	for j in CGrid.disc(c, 6):
		if not CFleet.is_sea(j) or CFleet.zone_owner(st, f, j) >= 0:
			continue
		var d := CGrid.d2(j, c)
		if d < bd or (d == bd and j < best):
			bd = d
			best = j
	return best


## End of turn: flota fleets at the exit leave the map and pay their
## treasure (event "flota_arrived", in the chronicle).
static func flota_arrivals(st: Dictionary) -> void:
	var ex := exit_cell()
	if ex < 0:
		return
	var gone: Array = []
	for fl in CFleet.fleets(st):
		if not is_flota(fl) or int(fl["flota"]) != 2 or CGrid.cheb(CFleet.cell(fl), ex) > 1:
			continue
		gone.append(fl)
	for fl in gone:
		var pays: Array = []
		var total := 0
		for s in fl["ships"]:
			var g := int(s.get("g", 0))
			if g <= 0:
				continue
			var f := int(s.get("o", int(fl["f"])))
			if not CState.alive(st, f):
				f = int(fl["f"])
			if not CState.alive(st, f):
				continue
			st["factions"][f]["treasury"] = int(st["factions"][f]["treasury"]) + g
			total += g
			var done := false
			for p in pays:
				if int(p[0]) == f:
					p[1] = int(p[1]) + g
					done = true
			if not done:
				pays.append([f, g])
		(st["fleets"] as Array).erase(fl)
		_stat(st, "flota_arrived", 1)
		_stat(st, "flota_gold", total)
		_rules().event(st, {"k": "flota_arrived", "f": int(fl["f"]), "gold": pays, "ships": (fl["ships"] as Array).size()})


## A sea battle's prize money: faction wf took `ships` (the ship dicts as
## they were, a treasure galleon with its "g") from faction `victim`.
## Returns [gold paid, treasure galleons among them].
static func prize_money(st: Dictionary, wf: int, victim: int, ships: Array, c: int = -1, capt: String = "") -> Array:
	var gold := 0
	var tg := 0
	var n := 0
	for s in ships:
		var row := CData.ship_row(str(s["t"]))
		var pct := k("PIRATE_PRIZE_PCT", 50) if pirate(wf) else k("PRIZE_PCT", 25)
		gold += int(row.get("cost", 0)) * pct / 100
		if int(s.get("g", 0)) > 0:
			gold += int(s["g"])
			tg += 1
			if s.has("nm"):  # (N2b) a named treasure galleon taken: a headline
				_stat(st, "galleons_taken", 1)
				var ev := {"k": "galleon_taken", "f": wf, "from": victim, "nm": str(s["nm"]), "g": int(s["g"]),
					"cap": int(s.get("cap", 0)), "x": CGrid.cx(c) if c >= 0 else -1, "y": CGrid.cy(c) if c >= 0 else -1}
				if capt != "":
					ev["capt"] = capt
				_rules().event(st, ev)
		n += 1
	var paid := gain(st, wf, gold, victim)
	if tg > 0:
		_stat(st, "treasure_taken", tg)
	add_infamy(st, wf, n * k("INFAMY_PRIZE", 3) + tg * k("INFAMY_TREASURE", 8))
	return [paid, tg]


# ------------------------------------------------------------------ sacks ---

## Region r was sacked in the last SACK_COOLDOWN turns.
static func sacked_lately(st: Dictionary, r: int) -> bool:
	var rs: Dictionary = st["regions"][r]
	return rs.has("sacked") and int(st["turn"]) - int(rs["sacked"]) < k("SACK_COOLDOWN", 8)


## Pirate faction f leaves region r alone for now (it sacked it lately).
static func spared(st: Dictionary, f: int, r: int) -> bool:
	return on(st) and pirate(f) and sacked_lately(st, r)


## Pirate faction f, winning an assault on region r, sacks it (rather than
## taking it): a port, by the faction's policy (auto: hold while it has
## fewer than PIRATE_HOLD regions and the port was not sacked lately).
static func sacks(st: Dictionary, r: int, f: int) -> bool:
	if not on(st) or not pirate(f) or CFleet.harbour(r) < 0:
		return false
	match int(st["factions"][f].get("sack_pol", 0)):
		1:
			return true
		2:
			return false
	return CState.regions_of(st, f).size() >= k("PIRATE_HOLD", 2)


## What a sack of region r by f would take now: [gold from the town, from
## the owner's treasury].
static func sack_gold(st: Dictionary, r: int) -> Array:
	var town := int(_rules()._base_income(st, r)) * k("SACK_TURNS", 3)
	var o := CState.owner(st, r)
	var tre := 0
	if o >= 0:
		tre = mini(maxi(int(st["factions"][o]["treasury"]), 0) * k("SACK_TREASURY_PCT", 15) / 100, k("SACK_TREASURY_MAX", 1000))
	if sacked_lately(st, r):
		town /= 4
		tre /= 4
	return [town, tre]


## Pirate faction f sacks region r (its armies `armies` won the assault):
## gold (town and the owner's treasury), every building a level down, the
## growth halved, construction lost; the owner keeps it; the pirates
## beside a fleet of theirs re-embark. Event "sack" (chronicle).
static func sack(st: Dictionary, r: int, f: int, armies: Array) -> void:
	var rs: Dictionary = st["regions"][r]
	var o := int(rs["owner"])
	var sg := sack_gold(st, r)
	if o >= 0:
		st["factions"][o]["treasury"] = int(st["factions"][o]["treasury"]) - int(sg[1])
	var paid := gain(st, f, int(sg[0]) + int(sg[1]), o)
	var slots: Array = []
	var hit := 0
	for s in rs["slots"]:
		if int(s[1]) > 1:
			slots.append([int(s[0]), int(s[1]) - 1])
		hit += 1
	rs["slots"] = slots
	rs["build"] = []
	rs["growth"] = int(rs["growth"]) / 2
	rs["gar"] = maxi(int(rs["gar"]), 10)
	rs["sacked"] = int(st["turn"])
	add_infamy(st, f, k("INFAMY_SACK", 12))
	CCaptain.sacked(st, f, r)  # (N2b) the captain who brought them gains fame
	_stat(st, "sacks", 1)
	_rules().event(st, {"k": "sack", "r": r, "f": f, "from": o, "gold": paid, "buildings": hit})
	for a in armies:
		_reembark(st, a)


## Army a (just out of a battle) boards a fleet of its faction beside it
## with room, if any (the lowest id).
static func _reembark(st: Dictionary, a: Dictionary) -> void:
	if CState.army_index(st, int(a["id"])) < 0:
		return
	for fl in CFleet.fleets_of(st, int(a["f"])):
		if is_flota(fl) or not CFleet.near_fleet(a, fl):
			continue
		if CFleet.carried_units(fl) + CState.unit_count(a) > CFleet.capacity(fl):
			continue
		var i := CState.army_index(st, int(a["id"]))
		(st["armies"] as Array).remove_at(i)
		_rules()._drop_march(a)
		a["busy"] = 0
		a["stance"] = CData.ST_DEFAULT
		(fl["carry"] as Array).append(a)
		_rules().event(st, {"k": "embarked", "f": int(a["f"]), "army": int(a["id"]), "fleet": int(fl["id"]), "r": int(a["r"])})
		return


## Order sack_policy {v}: 0 auto, 1 sack, 2 hold.
static func set_policy(st: Dictionary, f: int, v: int) -> String:
	if not on(st) or not pirate(f):
		return "only pirates sack"
	if v < 0 or v > 2:
		return "bad order"
	st["factions"][f]["sack_pol"] = v
	return ""


# -------------------------------------------------------- letters of marque ---

static func marques(st: Dictionary) -> Array:
	return st.get("marques", [])


## The letter between nation n and pirate p ([] none).
static func marque_of(st: Dictionary, a: int, b: int) -> Array:
	for m in marques(st):
		if (int(m[0]) == a and int(m[1]) == b) or (int(m[0]) == b and int(m[1]) == a):
			return m
	return []


static func has_marque(st: Dictionary, a: int, b: int) -> bool:
	return not marque_of(st, a, b).is_empty()


## "" if f may propose a letter of marque to g (one of them a pirate
## faction, the other not), else why not.
static func marque_check(st: Dictionary, f: int, g: int) -> String:
	if not on(st):
		return "no letters of marque here"
	if pirate(f) == pirate(g):
		return "only between a nation and pirates"
	if int(CData.FACTIONS[g if pirate(f) else f].get("no_marque", 0)) != 0:
		return "the Crown treats with no pirates"
	if has_marque(st, f, g):
		return "a letter is already sailing"
	return ""


## Nation n (one of a, b) grants pirate p a letter of marque: peace between
## them for MARQUE_TURNS turns (event "marque", chronicle).
static func grant(st: Dictionary, a: int, b: int) -> void:
	var p := a if pirate(a) else b
	var n := b if p == a else a
	if CState.dip(st, n, p) == CState.WAR:
		_rules().make_peace(st, n, p)
	if not st.has("marques"):
		st["marques"] = []
	var until := int(st["turn"]) + k("MARQUE_TURNS", 12)
	(st["marques"] as Array).append([n, p, until])
	_stat(st, "marques", 1)
	_rules().event(st, {"k": "marque", "a": n, "b": p, "until": until})


## End of turn: letters lapse at their turn, or are broken by war or a
## fall (event "marque_end": why "lapsed" | "broken").
static func marque_turn(st: Dictionary) -> void:
	if not st.has("marques"):
		return
	var keep: Array = []
	for m in st["marques"]:
		var n := int(m[0])
		var p := int(m[1])
		var why := ""
		if not CState.alive(st, n) or not CState.alive(st, p) or CState.dip(st, n, p) == CState.WAR:
			why = "broken"
		elif int(st["turn"]) >= int(m[2]):
			why = "lapsed"
		if why == "":
			keep.append(m)
		else:
			_rules().event(st, {"k": "marque_end", "a": n, "b": p, "why": why})
	st["marques"] = keep


## Why AI faction `to` would refuse a letter of marque from `from` ("" it
## accepts). A pirate takes one from a nation at war with another nation
## (someone to plunder); a nation grants one asked for while at war with
## another nation and the pirates' infamy is under MARQUE_INFAMY_MAX.
static func why_marque(st: Dictionary, from: int, to: int) -> String:
	var n := from if pirate(to) else to
	var p := to if pirate(to) else from
	if not _has_prey(st, n, p):
		return "no war to send privateers to"
	if pirate(to) and _letters(st, p) > 0:
		return "they already sail under another flag's letter"
	if not pirate(to) and infamy(st, p) >= k("MARQUE_INFAMY_MAX", 60):
		return "your infamy is too great (%d)" % infamy(st, p)
	return ""


## Letters of marque pirate faction p holds.
static func _letters(st: Dictionary, p: int) -> int:
	var n := 0
	for m in marques(st):
		if int(m[1]) == p:
			n += 1
	return n


## Nation n is at war with a nation other than pirates p (alive).
static func _has_prey(st: Dictionary, n: int, p: int) -> bool:
	for g in CState.nf():
		if g != n and g != p and not pirate(g) and CState.alive(st, g) and CState.at_war(st, n, g):
			return true
	return false


## A port of a nation that gave pirate fleet fl's faction a letter of
## marque, in whose harbour fl lies (within CFleet.PORT_CELLS), -1 none
## (privateers refit there).
static func patron_port(st: Dictionary, fl: Dictionary) -> int:
	var f := int(fl["f"])
	for m in marques(st):
		if int(m[1]) != f:
			continue
		var r := CFleet.port_of(st, fl, int(m[0]))
		if r >= 0:
			return r
	return -1


## AI nation f: offer a letter of marque to a pirate faction (cai.diplomacy).
## Returns the pirate faction to propose to, -1 none (one RNG draw per
## candidate).
static func marque_offer(st: Dictionary, f: int) -> int:
	if not on(st) or pirate(f):
		return -1
	for p in CState.nf():
		if not pirate(p) or not CState.alive(st, p) or marque_check(st, f, p) != "" or CState.friendly(st, f, p):
			continue
		if not _has_prey(st, f, p) or infamy(st, p) >= k("MARQUE_INFAMY_MAX", 60) or _letters(st, p) > 0:
			continue
		if CState.rand(st, 100) < k("MARQUE_ASK_CHANCE", 15):
			return p
	return -1


# ------------------------------------------------------------ end of turn ---

## crules.end_of_turn, before the money: the flota arrivals, the blockades.
static func before_money(st: Dictionary) -> void:
	if not on(st):
		return
	flota_arrivals(st)
	update_blockades(st)
	lane_events(st)


## crules.end_of_turn, last: infamy fades, letters lapse, the hurricanes
## (N2b), the captains (N2b), the next flota gathers.
static func after_turn(st: Dictionary) -> void:
	if not on(st):
		return
	for f in CState.nf():
		if pirate(f) and infamy(st, f) > 0:
			add_infamy(st, f, -k("INFAMY_DECAY", 1))
	marque_turn(st)
	CStorm.turn(st)  # (N2b) the hurricanes strike, move and form
	CCaptain.rise(st)  # (N2b) captainless pirate fleets find a captain
	flota_spawn(st)
