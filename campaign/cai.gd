extends RefCounted
## Campaign AI for the non-player factions (deterministic: reads the state,
## acts through the same rules as the players, uses only the state's RNG,
## iterates in index order). Independent regions never act.
##
## Each AI turn (act()):
##  1. merge armies standing together;
##  2. build: one construction per region, cheapest useful first, keeping a
##     reserve; walls where threatened, farms and markets for money, the
##     military buildings of its preferred lines in its recruiting centres;
##  3. recruit to a budget: army upkeep up to UPKEEP_SHARE of income (scaled by
##     the aggression setting and the number of wars), units by the faction's
##     preferred mix, best tier the buildings allow, where the armies are;
##  4. move: armies whose region is threatened stay; otherwise attack an
##     adjacent hostile region (land or sea) when the armies that can reach
##     it this turn are ATTACK_RATIO times its defence (garrison, armies there
##     and half the hostile armies next to it); else gather towards the best
##     target, or march to the frontier.
## With sieges (state version 4) the move step is _move_sieges(): first the
## sieges (join our sieges with free armies next to them; assault when the
## ratio is met, or when the garrison is starving and a relief army is near;
## lift and go home before a stronger relief army when the odds are poor;
## never maintain past the supplies + SIEGE_PATIENCE turns: then assault or
## lift; sally from our own besieged cities when garrison and armies inside
## outnumber the besiegers by the ratio; relieve them when the odds favour
## it), then attacks: assault when the ratio is met, else lay siege when the
## armies bring half the ratio and another army can arrive within two turns.
## Diplomacy (diplomacy()): peace when losing a long war, trade with
## neighbours at peace, and opportunistic wars on weaker neighbours, paced
## (no wars in the first turns, at most one new war on the players every few
## turns, few wars at a time).

const CData := preload("res://campaign/cdata.gd")
const CState := preload("res://campaign/cstate.gd")
const CRules := preload("res://campaign/crules.gd")
const CBattle := preload("res://campaign/cbattle.gd")
const UT := preload("res://sim/unit_types.gd")

const UPKEEP_SHARE := 70       # % of income spent on army upkeep at most
const ATTACK_RATIO := 150      # % of the target's defence needed to attack
const RESERVE_TURNS := 1       # keep this many turns of upkeep in the bank
const FIRST_WAR_TURN := 6      # no AI declares war before this turn
const FIRST_WAR_ON_PLAYERS := 10
const PLAYER_WAR_GAP := 8      # turns between AI war declarations on the players
const MAX_WARS := 2            # an AI starts no new war while at war with this many factions
const WAR_RATIO := 120         # % of a neighbour's strength needed to consider war on it ...
const WAR_RATIO_BUSY := 90     # ... if the neighbour is already at war
const WAR_CHANCE := 12         # % per turn per eligible neighbour
const WAR_CHANCE_PLAYERS := 8
const SIEGE_PATIENCE := 3      # turns past the supplies a siege is maintained before assault or lift
const RELIEF_WIN := 60         # % chance needed to relieve a besieged city
const SIEGE_ASSAULT_WIN := 35  # % chance to storm a siege that ran out of patience (else lift)


static func act(st: Dictionary, f: int) -> void:
	if not CState.alive(st, f) or CState.is_human(st, f):
		return
	_merge(st, f)
	_cut_debt(st, f)
	_build(st, f)
	_recruit(st, f)
	_move(st, f)


# ----------------------------------------------------------- assessment ---

## Strength of the hostile armies next to region r (land or sea), seen by f.
static func threat(st: Dictionary, f: int, r: int) -> int:
	var t := 0
	for e in CData.adjacent(r):
		for a in CState.armies_in(st, int(e[0])):
			if CState.at_war(st, f, int(a["f"])):
				t += CState.strength(a)
	return t


## Defence of region r: garrison (with walls and ground) and armies there.
static func defence(st: Dictionary, r: int) -> int:
	var o := CState.owner(st, r)
	var d := CBattle.garrison_strength(st, r)
	for a in CState.armies_in(st, r):
		if CState.friendly(st, int(a["f"]), o):
			d += CState.strength(a)
	return d * (100 + CBattle.ground_bonus(r)) / 100


static func faction_strength(st: Dictionary, f: int) -> int:
	var s := 0
	for a in st["armies"]:
		if int(a["f"]) == f:
			s += CState.strength(a)
	for r in CState.regions_of(st, f):
		s += CBattle.garrison_strength(st, r) / 3
	return s


static func wars(st: Dictionary, f: int) -> Array[int]:
	var out: Array[int] = []
	for g in CState.nf():
		if g != f and CState.alive(st, g) and CState.dip(st, f, g) == CState.WAR:
			out.append(g)
	return out


static func region_value(st: Dictionary, r: int) -> int:
	var v := int(CData.REGIONS[r]["wealth"]) * 100 + int(st["regions"][r]["level"]) * 150
	if CData.KEY_CITIES.has(str(CData.REGIONS[r]["key"])):
		v += 300
	return v


static func _aggr(st: Dictionary) -> int:
	return clampi(int(st["settings"].get("ai_aggression", 100)), 30, 200)


# ---------------------------------------------------------------- merge ---

static func _merge(st: Dictionary, f: int) -> void:
	var mine := CState.armies_of(st, f)
	for i in mine.size():
		var a: Dictionary = mine[i]
		if CState.army_index(st, int(a["id"])) < 0 or int(a["busy"]) != 0:
			continue
		for j in range(i + 1, mine.size()):
			var b: Dictionary = mine[j]
			if CState.army_index(st, int(b["id"])) < 0 or int(b["busy"]) != 0 or int(b["r"]) != int(a["r"]):
				continue
			if CState.unit_count(a) + CState.unit_count(b) <= CData.ARMY_MAX:
				CRules.apply_order(st, f, {"t": "merge", "army": int(b["id"]), "into": int(a["id"])})


## In debt with upkeep above income: disband the weakest units (the most
## depleted first) until upkeep fits the income.
static func _cut_debt(st: Dictionary, f: int) -> void:
	if int(st["factions"][f]["treasury"]) >= 0:
		return
	var inc := int(CRules.income(st, f)["total"])
	var up := CRules.upkeep(st, f)
	var guard := 0
	while up > inc * 90 / 100 and guard < 40:
		guard += 1
		var best_a := {}
		var best_k := -1
		var best_n := 1 << 30
		for a in CState.armies_of(st, f):
			if int(a["busy"]) != 0 or CRules.siege_role(st, a) != 0:
				continue
			for k in CState.unit_count(a):
				var n := int(a["units"][k]["n"]) * 100 / maxi(UT.size_of(CState.unit_type(a["units"][k])), 1)
				if n < best_n:
					best_n = n
					best_a = a
					best_k = k
		if best_k < 0:
			return
		up -= CState.upkeep_of(CState.unit_type(best_a["units"][best_k]))
		CRules.apply_order(st, f, {"t": "disband", "army": int(best_a["id"]), "units": [best_k]})


# ---------------------------------------------------------------- build ---

static func _reserve(st: Dictionary, f: int) -> int:
	return CRules.upkeep(st, f) * RESERVE_TURNS


static func _build(st: Dictionary, f: int) -> void:
	var regions := CState.regions_of(st, f)
	# Richest and capital first.
	regions.sort_custom(func(a, b):
		var va := region_value(st, a) + (1000 if CData.is_capital(a) else 0)
		var vb := region_value(st, b) + (1000 if CData.is_capital(b) else 0)
		return va > vb or (va == vb and a < b))
	var mix: Dictionary = CData.FACTIONS[f]["mix"]
	var spent := 0
	var budget := (int(st["factions"][f]["treasury"]) - _reserve(st, f)) * 60 / 100
	for r in regions:
		if not CState.battle_at(st, r).is_empty():
			continue
		var want: Array[int] = []
		var thr := threat(st, f, r)
		if thr > defence(st, r) / 2:
			want.append(CData.WALLS)
		var centre := CData.is_capital(r) or int(st["regions"][r]["level"]) >= CData.TOWN
		want.append(CData.FARM)
		want.append(CData.MARKET)
		if centre:
			for c in [CData.BARRACKS, CData.STABLES, CData.RANGE]:
				if _wants_chain(mix, c):
					want.append(c)
			if mix.has("bolt") or mix.has("stone"):
				want.append(CData.WORKSHOP)
		for c in want:
			var info := CRules.build_info(st, f, r, c)
			if info.has("why"):
				continue
			if spent + int(info["cost"]) > budget:
				continue
			if CRules.apply_order(st, f, {"t": "build", "r": r, "chain": c}) == "":
				spent += int(info["cost"])
				break


static func _wants_chain(mix: Dictionary, c: int) -> bool:
	for line in mix:
		if int(CData.LINE_CHAIN[line]) == c:
			return true
	return false


# -------------------------------------------------------------- recruit ---

static func _recruit(st: Dictionary, f: int) -> void:
	var fs: Dictionary = st["factions"][f]
	var inc := int(CRules.income(st, f)["total"])
	var share := UPKEEP_SHARE * _aggr(st) / 100
	if not wars(st, f).is_empty():
		share += 10
	# Money in the bank buys more army (a war chest of several turns'
	# income is spent down over time).
	if inc > 0:
		share += clampi(int(fs["treasury"]) * 10 / inc, 0, 40)
	var cap := inc * share / 100
	var up := CRules.upkeep(st, f)
	var mix: Dictionary = CData.FACTIONS[f]["mix"]
	# Where to recruit: regions with armies or on the frontier, richest
	# military buildings first.
	var regions := CState.regions_of(st, f)
	var scored: Array = []
	for r in regions:
		if not CState.battle_at(st, r).is_empty():
			continue
		var sc := 0
		for c in [CData.BARRACKS, CData.STABLES, CData.RANGE, CData.WORKSHOP]:
			sc += CState.building(st, r, c) * 10
		if sc == 0:
			continue
		sc += threat(st, f, r) / 500 + (5 if _frontier(st, f, r) else 0)
		scored.append([sc, r])
	scored.sort_custom(func(a, b): return a[0] > b[0] or (a[0] == b[0] and a[1] < b[1]))
	var guard := 0
	for e in scored:
		var r: int = e[1]
		while guard < 12:
			guard += 1
			var line := _next_line(st, f, mix)
			var key := _best_type(st, f, r, line)
			if key == "":
				key = _any_type(st, f, r)
			if key == "":
				break
			var ty := UT.index_of(key)
			if up + CState.upkeep_of(ty) > cap:
				return
			if int(fs["treasury"]) - UT.price_of(ty) < _reserve(st, f) / 2:
				return
			if CRules.apply_order(st, f, {"t": "recruit", "r": r, "unit": key}) != "":
				break
			up += CState.upkeep_of(ty)


## The line furthest below its share of the preferred mix.
static func _next_line(st: Dictionary, f: int, mix: Dictionary) -> String:
	var have := {}
	var total := 0
	for a in CState.armies_of(st, f):
		for u in a["units"]:
			var line := UT.line_of(CState.unit_type(u))
			have[line] = int(have.get(line, 0)) + 1
			total += 1
	for rs in st["regions"]:
		if int(rs["owner"]) == f:
			for k in rs["queue"]:
				var line := UT.line_of(UT.index_of(str(k)))
				have[line] = int(have.get(line, 0)) + 1
				total += 1
	var best := ""
	var best_gap := -100000
	for line in CData.LINE_ORDER:
		if not mix.has(line):
			continue
		var gap := int(mix[line]) * (total + 1) - int(have.get(line, 0)) * 100
		if gap > best_gap:
			best_gap = gap
			best = line
	return best


static func _best_type(st: Dictionary, f: int, r: int, line: String) -> String:
	for tier in [3, 2, 1]:
		var key := CState.roster_type(f, line, tier)
		if key != "" and CRules.recruit_check(st, f, r, key) == "":
			return key
	return ""


static func _any_type(st: Dictionary, f: int, r: int) -> String:
	for o in CRules.recruit_options(st, f, r):
		if o["ok"] and UT.cls(UT.index_of(str(o["t"]))) != UT.CLS_ART:
			return str(o["t"])
	return ""


# ----------------------------------------------------------------- move ---

static func _frontier(st: Dictionary, f: int, r: int) -> bool:
	for e in CData.adjacent(r):
		if CState.at_war(st, f, CState.owner(st, int(e[0]))):
			return true
	return false


## Defence a target region offers against faction f: its own defence plus
## half the hostile armies next to it (they may reinforce).
static func target_defence(st: Dictionary, f: int, t: int) -> int:
	var d := defence(st, t)
	var o := CState.owner(st, t)
	for e in CData.adjacent(t):
		if int(e[1]) != 0:
			continue
		for a in CState.armies_in(st, int(e[0])):
			if int(a["f"]) != f and CState.friendly(st, int(a["f"]), o) and o >= 0:
				d += CState.strength(a) / 2
	return d


## Distance to the frontier over friendly regions (multi-source BFS).
static func _frontier_dist(st: Dictionary, f: int) -> Array[int]:
	var nreg := CData.region_count()
	var dist: Array[int] = []
	dist.resize(nreg)
	dist.fill(999)
	var queue: Array[int] = []
	for r in nreg:
		if CState.friendly(st, f, CState.owner(st, r)) and _frontier(st, f, r):
			dist[r] = 0
			queue.append(r)
	var qi := 0
	while qi < queue.size():
		var r := queue[qi]
		qi += 1
		for e in CData.adjacent(r):
			var n := int(e[0])
			if dist[n] > dist[r] + 1 and CState.friendly(st, f, CState.owner(st, n)):
				dist[n] = dist[r] + 1
				queue.append(n)
	return dist


static func _move(st: Dictionary, f: int) -> void:
	if CState.sieges_on(st):
		_move_sieges(st, f)
		return
	var ratio := ATTACK_RATIO * 100 / _aggr(st)
	var nreg := CData.region_count()
	var dist := _frontier_dist(st, f)
	# Attack plans: for each hostile region next to our armies, the armies
	# that could reach it this turn.
	var targets: Array = []
	for t in nreg:
		var o := CState.owner(st, t)
		if not CState.at_war(st, f, o) or not CState.battle_at(st, t).is_empty():
			continue
		var reach: Array = []
		var power := 0
		for a in CState.armies_of(st, f):
			if int(a["busy"]) != 0 or int(a["moved"]) != 0:
				continue
			if CData.link(int(a["r"]), t) >= 0:
				reach.append(a)
				power += CState.strength(a)
		if reach.is_empty():
			continue
		var d := maxi(target_defence(st, f, t), 1)
		var val := region_value(st, t)
		if o >= 0 and CState.is_human(st, o):
			val = val * 90 / 100
		targets.append({"t": t, "def": d, "power": power, "reach": reach, "score": val * 1000 / d})
	targets.sort_custom(func(a, b): return a["score"] > b["score"] or (a["score"] == b["score"] and a["t"] < b["t"]))
	for tg in targets:
		if int(tg["power"]) * 100 < int(tg["def"]) * ratio:
			continue
		# Commit armies (strongest first) until the ratio is met, leaving
		# threatened home regions defended.
		var reach: Array = tg["reach"]
		reach.sort_custom(func(a, b): return CState.strength(a) > CState.strength(b) \
			or (CState.strength(a) == CState.strength(b) and int(a["id"]) < int(b["id"])))
		var sent := 0
		var go: Array = []
		for a in reach:
			if int(a["moved"]) != 0 or int(a["busy"]) != 0:
				continue
			if _must_hold(st, f, a):
				continue
			go.append(a)
			sent += CState.strength(a)
			if sent * 100 >= int(tg["def"]) * ratio * 13 / 10:
				break
		if sent * 100 < int(tg["def"]) * ratio:
			continue
		for a in go:
			CRules.execute_move(st, a, int(tg["t"]))
	# Remaining armies: gather towards the frontier.
	for a in CState.armies_of(st, f):
		if int(a["moved"]) != 0 or int(a["busy"]) != 0:
			continue
		var r := int(a["r"])
		if dist[r] == 0 or _must_hold(st, f, a):
			continue
		var best := -1
		for e in CData.adjacent(r):
			var n := int(e[0])
			if dist[n] < dist[r] and (best < 0 or dist[n] < dist[best]):
				if CRules.can_move(st, a, n) == "":
					best = n
		if best >= 0:
			CRules.execute_move(st, a, best)


# ---------------------------------------------------------------- sieges ---

## The move step with sieges (state version 4).
static func _move_sieges(st: Dictionary, f: int) -> void:
	var ratio := ATTACK_RATIO * 100 / _aggr(st)
	var nreg := CData.region_count()
	var dist := _frontier_dist(st, f)
	_sieges(st, f, ratio)
	# Attack plans, as in _move(); regions under siege are handled above.
	var targets: Array = []
	for t in nreg:
		var o := CState.owner(st, t)
		if not CState.at_war(st, f, o) or not CState.battle_at(st, t).is_empty() or not CState.siege_at(st, t).is_empty():
			continue
		var reach: Array = []
		var power := 0
		for a in CState.armies_of(st, f):
			if _free(st, a) and CData.link(int(a["r"]), t) >= 0:
				reach.append(a)
				power += CState.strength(a)
		if reach.is_empty():
			continue
		var d := maxi(target_defence(st, f, t), 1)
		var val := region_value(st, t)
		if o >= 0 and CState.is_human(st, o):
			val = val * 90 / 100
		targets.append({"t": t, "def": d, "power": power, "reach": reach, "score": val * 1000 / d})
	targets.sort_custom(func(a, b): return a["score"] > b["score"] or (a["score"] == b["score"] and a["t"] < b["t"]))
	for tg in targets:
		var t := int(tg["t"])
		var d := int(tg["def"])
		if int(tg["power"]) * 100 < d * ratio / 2:
			continue
		var reach: Array = tg["reach"]
		reach.sort_custom(func(a, b): return CState.strength(a) > CState.strength(b) \
			or (CState.strength(a) == CState.strength(b) and int(a["id"]) < int(b["id"])))
		var sent := 0
		var go: Array = []
		var assault := int(tg["power"]) * 100 >= d * ratio
		for a in reach:
			if not _free(st, a) or _must_hold(st, f, a):
				continue
			go.append(a)
			sent += CState.strength(a)
			if assault and sent * 100 >= d * ratio * 13 / 10:
				break
		if go.is_empty():
			continue
		var mode := CData.MODE_ASSAULT
		if sent * 100 < d * ratio:
			# Not enough to storm it: lay siege if another army can join
			# within two turns, else leave it.
			if sent * 100 < d * ratio / 2 or not _support_near(st, f, t, go):
				continue
			mode = CData.MODE_SIEGE
		for a in go:
			CRules.execute_move(st, a, t, mode)
	# Remaining armies: gather towards the frontier (never into one of our
	# besieged cities: that is a relief, decided above).
	for a in CState.armies_of(st, f):
		if not _free(st, a):
			continue
		var r := int(a["r"])
		if dist[r] == 0 or _must_hold(st, f, a):
			continue
		var best := -1
		for e in CData.adjacent(r):
			var n := int(e[0])
			if dist[n] < dist[r] and (best < 0 or dist[n] < dist[best]):
				if CRules.can_move(st, a, n) == "" and CState.siege_at(st, n).is_empty():
					best = n
		if best >= 0:
			CRules.execute_move(st, a, best)


## An army free to act: not in a battle, not moved, not in a siege.
static func _free(st: Dictionary, a: Dictionary) -> bool:
	return int(a["busy"]) == 0 and int(a["moved"]) == 0 and CRules.siege_role(st, a) == 0


## Another army of f (not in `go`) can reach a region next to t through
## friendly land within two turns.
static func _support_near(st: Dictionary, f: int, t: int, go: Array) -> bool:
	var ids: Array = []
	for a in go:
		ids.append(int(a["id"]))
	for a in CState.armies_of(st, f):
		if ids.has(int(a["id"])) or int(a["busy"]) != 0 or CRules.siege_role(st, a) != 0:
			continue
		var r := int(a["r"])
		if CData.link(r, t) >= 0:
			return true
		for e in CData.adjacent(r):
			var n := int(e[0])
			if CData.link(n, t) >= 0 and CState.friendly(st, f, CState.owner(st, n)):
				return true
	return false


## Strength of the armies of region r's owner's side next to r (a relief).
static func _relief_near(st: Dictionary, f: int, r: int) -> Array:
	var o := CState.owner(st, r)
	var out: Array = []
	if o < 0:
		return out
	for e in CData.adjacent(r):
		for a in CState.armies_in(st, int(e[0])):
			if CState.friendly(st, int(a["f"]), o) and CState.at_war(st, f, int(a["f"])) \
					and CRules.siege_role(st, a) == 0:
				out.append(a)
	return out


static func _sum(list: Array) -> int:
	var s := 0
	for a in list:
		s += CState.strength(a)
	return s


## Sieges for AI faction f: its own (join, assault, lift or maintain) and
## its besieged cities (sally or relieve).
static func _sieges(st: Dictionary, f: int, ratio: int) -> void:
	for sg in (st["sieges"] as Array).duplicate():
		var r := int(sg["r"])
		if CState.siege_at(st, r).is_empty() or not CState.battle_at(st, r).is_empty():
			continue
		var o := CState.owner(st, r)
		if int(sg["f"]) == f:
			_own_siege(st, f, sg, ratio)
		elif o == f:
			_besieged(st, f, r, ratio)


static func _own_siege(st: Dictionary, f: int, sg: Dictionary, ratio: int) -> void:
	var r := int(sg["r"])
	# Free armies next to the siege join it.
	for a in CState.armies_of(st, f):
		if _free(st, a) and CData.link(int(a["r"]), r) >= 0 and not _must_hold(st, f, a) \
				and CRules.can_move(st, a, r) == "":
			CRules.execute_move(st, a, r, CData.MODE_SIEGE)
	var bs := CRules.besiegers(st, r)
	if bs.is_empty():
		return
	var od := CBattle.odds(st, bs, CRules.besieged_armies(st, r), r, true)
	var relief := _relief_near(st, f, r)
	var starving := int(sg["supply"]) <= 0
	if int(od["att"]) * 100 >= int(od["def"]) * ratio or (starving and not relief.is_empty()):
		CRules.order_assault(st, f, r)
		return
	if not relief.is_empty() and _sum(relief) > _sum(bs):
		# A stronger army comes to relieve it: odds of that field battle
		# (relief, garrison and armies inside against us).
		var all := relief + CRules.besieged_armies(st, r)
		var ro := CBattle.odds(st, all, bs, r, false, 0)
		if int(ro["win"]) >= 50:
			_lift(st, f, sg)
			return
	if int(sg["held"]) >= CState.siege_supply(st, r) + SIEGE_PATIENCE:
		if int(od["win"]) >= SIEGE_ASSAULT_WIN:
			CRules.order_assault(st, f, r)
		else:
			_lift(st, f, sg)


## Lift a siege: every besieging army of f goes back where it came from (or
## to any friendly neighbour).
static func _lift(st: Dictionary, f: int, sg: Dictionary) -> void:
	var r := int(sg["r"])
	for a in CRules.besiegers(st, r):
		if int(a["f"]) != f or int(a["busy"]) != 0 or int(a["moved"]) != 0:
			continue
		var dest := -1
		var o := CRules._siege_origin(sg, int(a["id"]))
		if o >= 0 and CState.friendly(st, f, CState.owner(st, o)) and CState.siege_at(st, o).is_empty() \
				and CRules.can_move(st, a, o) == "":
			dest = o
		if dest < 0:
			for e in CData.adjacent(r):
				var n := int(e[0])
				if CState.friendly(st, f, CState.owner(st, n)) and CState.siege_at(st, n).is_empty() \
						and CRules.can_move(st, a, n) == "":
					dest = n
					break
		if dest >= 0:
			CRules.execute_move(st, a, dest, CData.MODE_SIEGE)


## Our city r is besieged: sally when the garrison and the armies inside
## outnumber the besiegers by the ratio, else relieve it when the odds of
## the free armies next to it (with the garrison and armies inside) favour
## us.
static func _besieged(st: Dictionary, f: int, r: int, ratio: int) -> void:
	var bs := CRules.besiegers(st, r)
	var inside := CRules.besieged_armies(st, r)
	var so := CBattle.odds(st, inside, bs, r, false, 0)
	if int(so["att"]) * 100 >= int(so["def"]) * ratio:
		CRules.order_sally(st, f, r)
		return
	var rel: Array = []
	for a in CState.armies_of(st, f):
		if _free(st, a) and CData.link(int(a["r"]), r) >= 0 and CRules.can_move(st, a, r) == "":
			rel.append(a)
	if rel.is_empty():
		return
	var ro := CBattle.odds(st, rel + inside, bs, r, false, 0)
	if int(ro["win"]) >= RELIEF_WIN:
		for a in rel:
			CRules.execute_move(st, a, r, CData.MODE_SIEGE)


## An army stays to defend its region if the threat there exceeds the
## defence without it (and the region is ours).
static func _must_hold(st: Dictionary, f: int, a: Dictionary) -> bool:
	var r := int(a["r"])
	if CState.owner(st, r) != f:
		return false
	var thr := threat(st, f, r)
	if thr == 0:
		return false
	return defence(st, r) - CState.strength(a) < thr


# ------------------------------------------------------------ diplomacy ---

## Would AI faction `to` accept `what` from faction `from`?
static func accepts(st: Dictionary, from: int, to: int, what: String) -> bool:
	var mine := faction_strength(st, to)
	var theirs := faction_strength(st, from)
	match what:
		"peace":
			var since := CState.dip_since(st, from, to)
			if since < 3:
				return false
			# Accept when not clearly winning, or after a long war.
			# Accept when not clearly winning, after a long war, or when
			# down to few regions.
			return mine * 100 < theirs * 100 or since >= 18 or CState.regions_of(st, to).size() <= 2
		"trade":
			return CState.dip_since(st, from, to) >= 2 and mine * 100 < theirs * 250
		"cancel_trade":
			return true
	return false


static func diplomacy(st: Dictionary, f: int) -> void:
	if not CState.alive(st, f) or CState.is_human(st, f):
		return
	var turn := int(st["turn"])
	var mine := faction_strength(st, f)
	var my_wars := wars(st, f)
	# Peace when losing a long war.
	for g in my_wars:
		if CState.dip_since(st, f, g) < 6:
			continue
		var theirs := faction_strength(st, g)
		if mine * 100 < theirs * 70 or CState.dip_since(st, f, g) >= 20:
			_propose(st, f, g, "peace")
	# Trade with neighbours at peace.
	for g in CState.nf():
		if g == f or not CState.alive(st, g) or CState.dip(st, f, g) != CState.PEACE:
			continue
		if CState.dip_since(st, f, g) >= 3 and _neighbours(st, f, g) and CState.rand(st, 100) < 15:
			_propose(st, f, g, "trade")
	# Opportunistic war.
	if turn < FIRST_WAR_TURN or my_wars.size() >= MAX_WARS:
		return
	var aggr := _aggr(st)
	for g in CState.nf():
		if g == f or not CState.alive(st, g) or CState.dip(st, f, g) == CState.WAR:
			continue
		if CState.friendly(st, f, g) or not _neighbours(st, f, g) or CState.dip_since(st, f, g) < 6:
			continue
		var theirs := faction_strength(st, g)
		# Weaker neighbours, or ones already fighting someone else.
		var busy := not wars(st, g).is_empty()
		if mine * 100 < theirs * (WAR_RATIO_BUSY if busy else WAR_RATIO):
			continue
		var chance := WAR_CHANCE * aggr / 100
		if CState.is_human(st, g):
			var last := int(st["stats"].get("last_war_on_players", -100))
			if turn < FIRST_WAR_ON_PLAYERS or turn - last < PLAYER_WAR_GAP:
				continue
			chance = WAR_CHANCE_PLAYERS * aggr / 100
		if CState.dip(st, f, g) == CState.TRADE:
			chance /= 2
		# Big realms start fewer wars.
		var owned := CState.regions_of(st, f).size()
		if owned > 8:
			chance = chance * 8 / owned
		if CState.rand(st, 100) < chance:
			CRules.declare_war(st, f, g)
			if CState.is_human(st, g):
				st["stats"]["last_war_on_players"] = turn
			return


static func _neighbours(st: Dictionary, f: int, g: int) -> bool:
	for r in CState.regions_of(st, f):
		for e in CData.adjacent(r):
			if CState.owner(st, int(e[0])) == g:
				return true
	return false


## Proposal from AI f to g: another AI answers at once; a player gets it in
## the state's proposals to answer next turn.
static func _propose(st: Dictionary, f: int, g: int, what: String) -> void:
	if CRules.check_proposal(st, f, g, what) != "":
		return
	if CState.is_human(st, g):
		for p in st["proposals"]:
			if int(p["from"]) == f and int(p["to"]) == g:
				return
		var id := int(st["next_proposal"])
		st["next_proposal"] = id + 1
		(st["proposals"] as Array).append({"id": id, "from": f, "to": g, "what": what, "turn": int(st["turn"])})
		CRules.event(st, {"k": "proposal", "from": f, "to": g, "what": what, "id": id})
		return
	if accepts(st, f, g, what):
		CRules.apply_agreement(st, f, g, what)
