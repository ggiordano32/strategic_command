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
## With the continuous overworld (state version 6) the move step is
## _move_grid() (see there: static distance fields, hunting field armies,
## gathering, raids in the raiding stance, screens, forced marches,
## fortifying); it runs before the recruiting, which then puts recruits
## only into armies that hold this turn or raises a new army (the mustering
## rule, _recruit_order).
## Diplomacy (diplomacy()): peace when losing a long war, trade with
## neighbours at peace, and opportunistic wars on weaker neighbours, paced
## (no wars in the first turns, at most one new war on the players every few
## turns, few wars at a time).
## Easy (docs/AI.md 9; knobs of campaign/cai_profile.gd, the overworld of
## version 6 mainly): cheapest building first, piecemeal recruiting leaning
## to the line it already has, the nearest targets first at lower odds,
## armies sent as they are (no gathering, a turn apart), assaults on
## arrival, no screens, relief, raids or stances, no peace proposals; and
## the deliberate mistakes rolled with CState.rand (_mistake): an army
## marching off from a threatened city or a fresh conquest, one attack at
## poor odds, a turn of recruiting past the income, a war on a stronger
## neighbour. A level whose chance of a mistake is 0 never draws for it.
## Skilled (docs/AI.md 12; the SK_* knobs, 0 at Easy and Average, so those
## levels never run the code below that they gate): hunts count the
## target's supporters within support range (_supporters) and take
## intercepts of a relief at lower odds; the spare armies merge into or
## stand by the strongest army (_rally); gathering points out of the
## enemy's reach next turn and armies the enemy could fall on fall back to
## support (_foes6, _danger, _fall_back); a siege is stormed before a
## relief that can arrive next turn (_relief_soon); recruits lean to what
## beats the enemies' armies (_counter_mix); wars wait for the neighbour's
## armies to be away from the border (_border_weak) and a second front is
## closed by a peace offer (_one_front). It never shelters inside the walls
## (SHELTER_PCT 0: measured, the army is lost with the city).

const CData := preload("res://campaign/cdata.gd")
const CState := preload("res://campaign/cstate.gd")
const CRules := preload("res://campaign/crules.gd")
const CBattle := preload("res://campaign/cbattle.gd")
const UT := preload("res://sim/unit_types.gd")
const CGrid := preload("res://campaign/cgrid.gd")
const CP := preload("res://campaign/cai_profile.gd")

# Every ratio, odds cutoff, turn count, share and weight the AI decides with
# is a knob of the faction's skill / personality profile
# (campaign/cai_profile.gd, read as kn[CP.X] with kn = CP.of(st, f)); the
# names in capitals in the comments are those knobs.


## moves (state version 5): the faction's move orders are appended here
## ([army, dest, faction, mode, persist]) and run later with every AI
## faction's moves in rounds (cturn step 5); older states move at once.
static func act(st: Dictionary, f: int, moves: Array = []) -> void:
	if not CState.alive(st, f) or CState.is_human(st, f):
		return
	_merge(st, f)
	_cut_debt(st, f)
	_build(st, f)
	if CState.grid_on(st):
		# Version 6: the moves are planned first, so the recruits go into
		# armies that hold this turn (the mustering rule: an army taking
		# recruits cannot march this turn; see _recruit_order).
		_move_grid(st, f, moves)
		_recruit(st, f, moves)
		return
	_recruit(st, f)
	if CState.moves_on(st):
		_move_free(st, f, moves)
	else:
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


## Value of region r to faction f (f < 0: the default profile's weights).
static func region_value(st: Dictionary, r: int, f: int = -1) -> int:
	var kn := CP.of(st, f)
	var v := int(CData.REGIONS[r]["wealth"]) * kn[CP.VAL_WEALTH] + int(st["regions"][r]["level"]) * kn[CP.VAL_LEVEL]
	if CData.KEY_CITIES.has(str(CData.REGIONS[r]["key"])):
		v += kn[CP.VAL_KEY]
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
			if CState.army_index(st, int(b["id"])) < 0 or int(b["busy"]) != 0:
				continue
			if CState.grid_on(st):
				if CGrid.cheb(CState.cell(a), CState.cell(b)) > 1:
					continue
			elif int(b["r"]) != int(a["r"]):
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
	var keep_pct := CP.of(st, f)[CP.CUT_DEBT_PCT]
	while up > inc * keep_pct / 100 and guard < 40:
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
	return CRules.upkeep(st, f) * CP.of(st, f)[CP.RESERVE_TURNS]


static func _build(st: Dictionary, f: int) -> void:
	var regions := CState.regions_of(st, f)
	var kn := CP.of(st, f)
	var cap_w: int = kn[CP.BUILD_CAPITAL_W]
	# Richest and capital first.
	regions.sort_custom(func(a, b):
		var va := region_value(st, a, f) + (cap_w if CData.is_capital(a) else 0)
		var vb := region_value(st, b, f) + (cap_w if CData.is_capital(b) else 0)
		return va > vb or (va == vb and a < b))
	var mix: Dictionary = CData.FACTIONS[f]["mix"]
	var spent := 0
	var budget := (int(st["factions"][f]["treasury"]) - _reserve(st, f)) * kn[CP.BUILD_BUDGET_PCT] / 100
	for r in regions:
		if not CState.battle_at(st, r).is_empty():
			continue
		var want: Array[int] = []
		var thr := threat(st, f, r)
		if thr > defence(st, r) / kn[CP.WALLS_THREAT_DIV]:
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
		if kn[CP.BUILD_CHEAPEST] != 0:
			want = _by_cost(st, f, r, want)
		for c in want:
			var info := CRules.build_info(st, f, r, c)
			if info.has("why"):
				continue
			if spent + int(info["cost"]) > budget:
				continue
			if CRules.apply_order(st, f, {"t": "build", "r": r, "chain": c}) == "":
				spent += int(info["cost"])
				break


## The chains of `want` that can be built in r, cheapest first (ties: the
## order given).
static func _by_cost(st: Dictionary, f: int, r: int, want: Array[int]) -> Array[int]:
	var keyed: Array = []
	for k in want.size():
		var info := CRules.build_info(st, f, r, want[k])
		if not info.has("why"):
			keyed.append([int(info["cost"]), k, want[k]])
	keyed.sort_custom(func(a, b): return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1]))
	var out: Array[int] = []
	for e in keyed:
		out.append(int(e[2]))
	return out


static func _wants_chain(mix: Dictionary, c: int) -> bool:
	for line in mix:
		if int(CData.LINE_CHAIN[line]) == c:
			return true
	return false


# -------------------------------------------------------------- recruit ---

## moves (version 6): the faction's planned moves (_move_grid), so each
## recruit goes into an army that holds (_recruit_order).
static func _recruit(st: Dictionary, f: int, moves: Array = []) -> void:
	var fs: Dictionary = st["factions"][f]
	var inc := int(CRules.income(st, f)["total"])
	var kn := CP.of(st, f)
	var share := kn[CP.UPKEEP_SHARE] * _aggr(st) / 100
	if not wars(st, f).is_empty():
		share += kn[CP.WAR_SHARE]
	# Money in the bank buys more army (a war chest of several turns'
	# income is spent down over time).
	if inc > 0:
		share += clampi(int(fs["treasury"]) * kn[CP.CHEST_SHARE] / inc, 0, kn[CP.CHEST_SHARE_MAX])
	var cap := inc * share / 100
	# Mistake: recruiting past the income this turn (the debt rules follow).
	if inc > 0 and _mistake(st, f, kn, CP.M_OVER_RECRUIT):
		cap = maxi(cap, inc * kn[CP.OVER_RECRUIT_PCT] / 100)
	var up := CRules.upkeep(st, f)
	var mix: Dictionary = CData.FACTIONS[f]["mix"]
	if kn[CP.SK_COUNTER_MIX] > 0:
		mix = _counter_mix(st, f, mix, kn)
	# Where to recruit: regions with armies or on the frontier, richest
	# military buildings first.
	var regions := CState.regions_of(st, f)
	var scored: Array = []
	for r in regions:
		if not CState.battle_at(st, r).is_empty():
			continue
		var sc := 0
		for c in [CData.BARRACKS, CData.STABLES, CData.RANGE, CData.WORKSHOP]:
			sc += CState.building(st, r, c) * kn[CP.RECRUIT_BUILDING_W]
		if sc == 0:
			continue
		sc += threat(st, f, r) / kn[CP.RECRUIT_THREAT_DIV] + (kn[CP.RECRUIT_FRONTIER_W] if _frontier(st, f, r) else 0)
		scored.append([sc, r])
	scored.sort_custom(func(a, b): return a[0] > b[0] or (a[0] == b[0] and a[1] < b[1]))
	var marching := {}  # version 6: army id -> 1, planned to march this turn
	if CState.grid_on(st):
		for mv in moves:
			if int(mv[2]) == f:
				marching[int(mv[0])] = 1
	var guard := 0
	for e in scored:
		var r: int = e[1]
		while guard < kn[CP.RECRUIT_MAX]:
			guard += 1
			var line := _next_line(st, f, mix)
			var lean := kn[CP.RECRUIT_LEAN_PCT]
			if lean > 0 and CState.rand(st, 100) < lean:
				line = _most_line(st, f, mix)  # more of what it already has
			var key := _best_type(st, f, r, line)
			if key == "":
				key = _any_type(st, f, r)
			if key == "":
				break
			var ty := UT.index_of(key)
			if up + CState.upkeep_of(ty) > cap:
				return
			if int(fs["treasury"]) - UT.price_of(ty) < _reserve(st, f) / kn[CP.RECRUIT_RESERVE_DIV]:
				return
			if CRules.apply_order(st, f, _recruit_order(st, f, r, key, marching, moves, kn)) != "":
				break
			up += CState.upkeep_of(ty)


## The recruit order for unit key in region r. Formats 1-5: the old form.
## Version 6 (the mustering rule: an army taking recruits cannot march this
## turn): into the first army of ours on or next to the settlement, with
## room, that is not planned to march (a garrison, an army parked there);
## else, when every such army marches, into one of at most
## RECRUIT_HOLD_UNITS units marching within our lands (its march is taken
## back: it stays and fills up), else the recruits raise a new army ("new":
## 1); with no army there at all, the old form (it joins no army now).
## marching: army id -> 1 (updated); moves: the planned moves (updated).
static func _recruit_order(st: Dictionary, f: int, r: int, key: String, marching: Dictionary, moves: Array,
		kn: PackedInt32Array) -> Dictionary:
	var o := {"t": "recruit", "r": r, "unit": key}
	if not CState.grid_on(st):
		return o
	var site := CGrid.site(r)
	var hold := -1
	var small := -1
	var any_march := false
	for a in st["armies"]:
		if int(a["f"]) != f or int(a["busy"]) != 0 or CGrid.cheb(CState.cell(a), site) > 1:
			continue
		var id := int(a["id"])
		if CRules.army_recruit_check(st, f, r, id) != "":
			continue
		if not marching.has(id):
			hold = id
			break
		any_march = true
		if small < 0 and CState.unit_count(a) + CRules.queued_into(st, id) <= kn[CP.RECRUIT_HOLD_UNITS] \
				and _home_march(st, f, moves, id):
			small = id
	if hold < 0 and small >= 0:
		hold = small
		marching.erase(small)
		for k in range(moves.size() - 1, -1, -1):
			if int(moves[k][0]) == small:
				moves.remove_at(k)
	if hold >= 0:
		o["army"] = hold
	elif any_march:
		o["new"] = 1
	return o


## Army id's planned move is a march within friendly lands (to a cell, not
## after an enemy army): taking it back costs no attack.
static func _home_march(st: Dictionary, f: int, moves: Array, id: int) -> bool:
	for mv in moves:
		if int(mv[0]) != id:
			continue
		var r := CGrid.region(int(mv[1]))
		if int(mv[1]) < 0 or r < 0 or ((mv as Array).size() > 5 and int(mv[5]) >= 0):
			return false
		if not CState.friendly(st, f, CState.owner(st, r)):
			return false
	return true


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


## The line of the preferred mix that faction f's armies hold most units of
## (ties: CData.LINE_ORDER).
static func _most_line(st: Dictionary, f: int, mix: Dictionary) -> String:
	var have := {}
	for a in CState.armies_of(st, f):
		for u in a["units"]:
			var line := UT.line_of(CState.unit_type(u))
			have[line] = int(have.get(line, 0)) + 1
	var best := ""
	var best_n := -1
	for line in CData.LINE_ORDER:
		if mix.has(line) and int(have.get(line, 0)) > best_n:
			best_n = int(have.get(line, 0))
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
	var kn := CP.of(st, f)
	var ratio := kn[CP.ATTACK_RATIO] * 100 / _aggr(st)
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
		var val := region_value(st, t, f)
		if o >= 0 and CState.is_human(st, o):
			val = val * kn[CP.HUMAN_VALUE_PCT] / 100
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
			if sent * 100 >= int(tg["def"]) * ratio * kn[CP.COMMIT_PCT] / 100:
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
	var kn := CP.of(st, f)
	var ratio := kn[CP.ATTACK_RATIO] * 100 / _aggr(st)
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
		var val := region_value(st, t, f)
		if o >= 0 and CState.is_human(st, o):
			val = val * kn[CP.HUMAN_VALUE_PCT] / 100
		targets.append({"t": t, "def": d, "power": power, "reach": reach, "score": val * 1000 / d})
	targets.sort_custom(func(a, b): return a["score"] > b["score"] or (a["score"] == b["score"] and a["t"] < b["t"]))
	for tg in targets:
		var t := int(tg["t"])
		var d := int(tg["def"])
		if int(tg["power"]) * 100 < d * ratio * kn[CP.SIEGE_RATIO_PCT] / 100:
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
			if assault and sent * 100 >= d * ratio * kn[CP.COMMIT_PCT] / 100:
				break
		if go.is_empty():
			continue
		var mode := CData.MODE_ASSAULT
		if sent * 100 < d * ratio:
			# Not enough to storm it: lay siege if another army can join
			# within two turns, else leave it.
			if sent * 100 < d * ratio * kn[CP.SIEGE_RATIO_PCT] / 100 or not _support_near(st, f, t, go):
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
	var kn := CP.of(st, f)
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
		if int(ro["win"]) >= kn[CP.LIFT_WIN]:
			_lift(st, f, sg)
			return
	if int(sg["held"]) >= CState.siege_supply(st, r) + kn[CP.SIEGE_PATIENCE]:
		if int(od["win"]) >= kn[CP.SIEGE_ASSAULT_WIN]:
			if int(od["win"]) < 50:
				CP.count(CP.C_BAD_ODDS, f)
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
	if int(ro["win"]) >= CP.of(st, f)[CP.RELIEF_WIN]:
		for a in rel:
			CRules.execute_move(st, a, r, CData.MODE_SIEGE)



# ------------------------------------------------- free movement (v5) ---

## The move step with free movement (state version 5). Plans only: the
## moves go to `out` and run in rounds after every AI faction has planned.
##  1. sieges: ours (join with armies that reach it this turn, assault at
##     the ratio or when starving with a relief near, lift before a
##     stronger relief, patience) and our besieged cities (sally, relieve);
##  2. attacks: per target (best value per defence first) the armies that
##     reach it this turn assault at the ratio, lay siege at half of it
##     with support near; if the ratio needs armies a turn further away,
##     they gather on a friendly region next to it first (concentrate);
##  3. armies idle IDLE_TURNS turns take a target with IDLE_WIN % odds;
##  4. one raid a turn into a rich enemy region with no field army in it;
##  5. screens: a free army that can match a threat to one of our cities
##     marches there and stands in the field (it intercepts);
##  6. the rest march towards the frontier (multi-hop);
##  7. stance: armies staying in our regions shelter inside the walls when
##     the enemy within a turn's march is much stronger, else take the field.
static func _move_free(st: Dictionary, f: int, out: Array) -> void:
	var kn := CP.of(st, f)
	var ratio := kn[CP.ATTACK_RATIO] * 100 / _aggr(st)
	var nreg := CData.region_count()
	var ok := _passable(st, f)
	var rcs := {}
	var free: Array = []
	for a in CState.armies_of(st, f):
		if int(a["busy"]) != 0:
			continue
		a["dest"] = -1
		a["mode"] = CData.MODE_MARCH
		if int(a["moved"]) != 0 or CRules.siege_role(st, a) == 2:
			continue
		rcs[int(a["id"])] = _reach(st, a, ok)
		free.append(a)
	var cx := _context(st, f)
	var used := {}
	_sieges_free(st, f, ratio, free, rcs, used, out, cx)
	# Attack plans.
	var targets: Array = []
	for t in nreg:
		var o := CState.owner(st, t)
		if not CState.at_war(st, f, o) or not CState.battle_at(st, t).is_empty() or not CState.siege_at(st, t).is_empty():
			continue
		var now: Array = []
		var soon: Array = []
		for a in free:
			var id := int(a["id"])
			if used.has(id) or CRules.siege_role(st, a) != 0:
				continue
			var tt := int(rcs[id]["t"][t])
			if tt == 0:
				now.append(a)
			elif tt == 1:
				soon.append(a)
		if now.is_empty() and soon.is_empty():
			continue
		var d := maxi(target_defence(st, f, t), 1)
		var val := region_value(st, t, f)
		if o >= 0 and CState.is_human(st, o):
			val = val * kn[CP.HUMAN_VALUE_PCT] / 100
		targets.append({"t": t, "def": d, "now": now, "soon": soon, "score": val * 1000 / d})
	targets.sort_custom(func(x, y): return x["score"] > y["score"] or (x["score"] == y["score"] and x["t"] < y["t"]))
	for tg in targets:
		_attack(st, f, tg, ratio, rcs, used, out, cx)
	# Idle armies take a fair chance.
	for a in free:
		var id := int(a["id"])
		if used.has(id) or int(a.get("idle", 0)) < kn[CP.IDLE_TURNS] or CRules.siege_role(st, a) != 0 or _hold(cx, st, f, a):
			continue
		var best := -1
		var best_v := 0
		var best_win := 0
		for tg in targets:
			var t := int(tg["t"])
			if int(rcs[id]["t"][t]) != 0 or not CState.siege_at(st, t).is_empty() or not CState.battle_at(st, t).is_empty():
				continue
			var od := CBattle.odds(st, [a], _defenders(st, t), t, true)
			if int(od["win"]) >= kn[CP.IDLE_WIN] and region_value(st, t, f) > best_v:
				best_v = region_value(st, t, f)
				best = t
				best_win = int(od["win"])
		if best >= 0:
			used[id] = 1
			if best_win < 50:
				CP.count(CP.C_BAD_ODDS, f)
			out.append([id, best, f, CData.MODE_SIEGE, 0])
	_raid(st, f, free, rcs, used, out, cx)
	_screen(st, f, free, rcs, used, out, cx)
	# The rest march towards the frontier.
	var dist := _frontier_dist(st, f)
	for a in free:
		var id := int(a["id"])
		if used.has(id) or CRules.siege_role(st, a) != 0:
			continue
		var r := int(a["r"])
		if dist[r] == 0 or _hold(cx, st, f, a):
			continue
		var rc: Dictionary = rcs[id]
		var best := -1
		for n in nreg:
			if dist[n] != 0 or int(rc["t"][n]) >= CRules.INF or not CState.siege_at(st, n).is_empty() \
					or not CState.friendly(st, f, CState.owner(st, n)):
				continue
			if best < 0 or int(rc["t"][n]) < int(rc["t"][best]) \
					or (int(rc["t"][n]) == int(rc["t"][best]) and int(rc["m"][n]) > int(rc["m"][best])):
				best = n
		if best >= 0:
			used[id] = 1
			out.append([id, best, f, CData.MODE_MARCH, 0])
	_stances(st, f, used, cx)


## Regions faction f may enter (1) or not (0), for _reach.
static func _passable(st: Dictionary, f: int) -> Array[int]:
	var ok: Array[int] = []
	for r in CData.region_count():
		ok.append(1 if CRules.can_enter(st, f, r) == "" else 0)
	return ok


## CRules.reach with the faction's passability computed once.
static func _reach(st: Dictionary, a: Dictionary, ok: Array[int]) -> Dictionary:
	return CRules.reach(st, a, false, ok)


## Armies of region r's owner's side there (the defenders of its settlement).
static func _defenders(st: Dictionary, r: int) -> Array:
	var o := CState.owner(st, r)
	var out: Array = []
	if o < 0:
		return out
	for a in CState.armies_in(st, r):
		if CState.friendly(st, int(a["f"]), o):
			out.append(a)
	return out


static func _attack(st: Dictionary, f: int, tg: Dictionary, ratio: int, rcs: Dictionary, used: Dictionary, out: Array, cx: Dictionary) -> void:
	var t := int(tg["t"])
	var d := int(tg["def"])
	var kn := CP.of(st, f)
	var commit := d * ratio * kn[CP.COMMIT_PCT] / 100
	var now: Array = []
	var soon: Array = []
	for a in tg["now"]:
		if not used.has(int(a["id"])) and not _hold(cx, st, f, a):
			now.append(a)
	for a in tg["soon"]:
		if not used.has(int(a["id"])) and not _hold(cx, st, f, a):
			soon.append(a)
	var sm: Dictionary = cx["str"]
	var by_strength := func(x, y): return int(sm[int(x["id"])]) > int(sm[int(y["id"])]) \
		or (int(sm[int(x["id"])]) == int(sm[int(y["id"])]) and int(x["id"]) < int(y["id"]))
	now.sort_custom(by_strength)
	soon.sort_custom(by_strength)
	var p_now := 0
	var p_soon := 0
	for a in now:
		p_now += _str(cx, a)
	for a in soon:
		p_soon += _str(cx, a)
	if p_now * 100 >= d * ratio:
		var sent := 0
		var n_sent := 0
		for a in now:
			used[int(a["id"])] = 1
			out.append([int(a["id"]), t, f, CData.MODE_ASSAULT, 0])
			sent += _str(cx, a)
			n_sent += 1
			if sent * 100 >= commit:
				break
		if n_sent == 1 and not soon.is_empty():
			CP.count(CP.C_TRICKLED, f)
		return
	if p_now * 100 >= d * ratio * kn[CP.SIEGE_RATIO_PCT] / 100 and not now.is_empty() and (not soon.is_empty() or now.size() > 1):
		for a in now:
			used[int(a["id"])] = 1
			out.append([int(a["id"]), t, f, CData.MODE_SIEGE, 0])
		return
	if soon.is_empty() or (p_now + p_soon) * 100 < d * ratio:
		return
	# Concentrate: gather on our side of the border next to t, attack next turn.
	var stage := -1
	for e in CData.adjacent(t):
		var n := int(e[0])
		if int(e[1]) != 0 or not CState.friendly(st, f, CState.owner(st, n)) or not CState.siege_at(st, n).is_empty():
			continue
		if stage < 0:
			stage = n
	if stage < 0:
		return
	var sent2 := 0
	for a in now + soon:
		var id := int(a["id"])
		used[id] = 1
		if int(a["r"]) != stage and int(rcs[id]["t"][stage]) == 0:
			out.append([id, stage, f, CData.MODE_MARCH, 0])
		sent2 += _str(cx, a)
		if sent2 * 100 >= commit:
			break


## Version 5 sieges: ours and our besieged cities (see _sieges for the
## rules; armies reach by path this turn instead of being adjacent).
static func _sieges_free(st: Dictionary, f: int, ratio: int, free: Array, rcs: Dictionary, used: Dictionary, out: Array, cx: Dictionary) -> void:
	for sg in (st["sieges"] as Array).duplicate():
		var r := int(sg["r"])
		if CState.siege_at(st, r).is_empty() or not CState.battle_at(st, r).is_empty():
			continue
		var o := CState.owner(st, r)
		if int(sg["f"]) == f:
			var bs := CRules.besiegers(st, r)
			var join: Array = []
			for a in free:
				var id := int(a["id"])
				if not used.has(id) and CRules.siege_role(st, a) == 0 and int(rcs[id]["t"][r]) == 0 and not _hold(cx, st, f, a):
					join.append(a)
			var od := CBattle.odds(st, bs + join, CRules.besieged_armies(st, r), r, true)
			var relief := _relief_near(st, f, r)
			var starving := int(sg["supply"]) <= 0
			var storm := int(od["att"]) * 100 >= int(od["def"]) * ratio or (starving and not relief.is_empty())
			var kn := CP.of(st, f)
			var lift := false
			if not storm and not relief.is_empty() and _sum(relief) > _sum(bs + join):
				var ro := CBattle.odds(st, relief + CRules.besieged_armies(st, r), bs + join, r, false, 0)
				lift = int(ro["win"]) >= kn[CP.LIFT_WIN]
			if not storm and not lift and int(sg["held"]) >= CState.siege_supply(st, r) + kn[CP.SIEGE_PATIENCE]:
				storm = int(od["win"]) >= kn[CP.SIEGE_ASSAULT_WIN]
				lift = not storm
				if storm and int(od["win"]) < 50:
					CP.count(CP.C_BAD_ODDS, f)
			if lift:
				for a in bs:
					if int(a["f"]) != f or int(a["busy"]) != 0 or int(a["moved"]) != 0 or not rcs.has(int(a["id"])):
						continue
					var back := _way_home(st, f, a, sg, rcs[int(a["id"])])
					if back >= 0:
						used[int(a["id"])] = 1
						out.append([int(a["id"]), back, f, CData.MODE_MARCH, 0])
				continue
			for a in join:
				used[int(a["id"])] = 1
				out.append([int(a["id"]), r, f, CData.MODE_ASSAULT if storm else CData.MODE_SIEGE, 0])
			for a in bs:
				used[int(a["id"])] = 1
			if storm and join.is_empty():
				CRules.order_assault(st, f, r)
		elif o == f:
			var bs2 := CRules.besiegers(st, r)
			var inside := CRules.besieged_armies(st, r)
			var so := CBattle.odds(st, inside, bs2, r, false, 0)
			if int(so["att"]) * 100 >= int(so["def"]) * ratio:
				CRules.order_sally(st, f, r)
				continue
			var rel: Array = []
			for a in free:
				var id := int(a["id"])
				if not used.has(id) and CRules.siege_role(st, a) == 0 and int(rcs[id]["t"][r]) == 0:
					rel.append(a)
			if rel.is_empty():
				continue
			var ro2 := CBattle.odds(st, rel + inside, bs2, r, false, 0)
			if int(ro2["win"]) >= CP.of(st, f)[CP.RELIEF_WIN]:
				for a in rel:
					used[int(a["id"])] = 1
					out.append([int(a["id"]), r, f, CData.MODE_MARCH, 0])


## Where a besieger lifting a siege goes: where it came from if friendly,
## else the nearest friendly region it can reach (-1 none).
static func _way_home(st: Dictionary, f: int, a: Dictionary, sg: Dictionary, rc: Dictionary) -> int:
	var o := CRules._siege_origin(sg, int(a["id"]))
	if o >= 0 and CState.friendly(st, f, CState.owner(st, o)) and CState.siege_at(st, o).is_empty() \
			and int(rc["t"][o]) < CRules.INF:
		return o
	var best := -1
	for n in CData.region_count():
		if not CState.friendly(st, f, CState.owner(st, n)) or not CState.siege_at(st, n).is_empty() or int(rc["t"][n]) >= CRules.INF:
			continue
		if best < 0 or int(rc["t"][n]) < int(rc["t"][best]) or (int(rc["t"][n]) == int(rc["t"][best]) and int(rc["m"][n]) > int(rc["m"][best])):
			best = n
	return best


## What faction f's planning reads many times, computed once: per region
## "thr" the strength of the enemy (at war) armies that can reach it this
## turn, roughly (within their points' worth of land routes, or across one
## sea lane), "foe" 1 if an enemy army stands there in the field, "here" 1
## if any enemy army stands there; "str" strength per army id (ours and
## enemies), "hold" _must_hold per army id (filled on demand).
static func _context(st: Dictionary, f: int) -> Dictionary:
	var n := CData.region_count()
	var thr: Array[int] = []
	var foe: Array[int] = []
	var here: Array[int] = []
	thr.resize(n)
	foe.resize(n)
	here.resize(n)
	thr.fill(0)
	foe.fill(0)
	here.fill(0)
	var sm := {}
	for a in st["armies"]:
		var s := CState.strength(a)
		sm[int(a["id"])] = s
		if int(a["busy"]) != 0 or not CState.at_war(st, f, int(a["f"])):
			continue
		var ar := int(a["r"])
		here[ar] = 1
		if CState.stance(a) == CData.STANCE_FIELD:
			foe[ar] = 1
		for r in _near(ar, CState.max_mp(a) / CData.COST_OPEN):
			thr[r] += s
	return {"thr": thr, "foe": foe, "here": here, "str": sm, "hold": {}}


static var _near_memo := {}


## Regions within `hops` land routes of r, or across one sea lane (r too).
static func _near(r: int, hops: int) -> Array[int]:
	var key := r * 16 + hops
	if _near_memo.has(key):
		return _near_memo[key]
	var out: Array[int] = []
	for x in CData.region_count():
		if x == r or CRules.land_hops(r, x) <= hops or CData.link(r, x) >= 0:
			out.append(x)
	_near_memo[key] = out
	return out


static func _str(cx: Dictionary, a: Dictionary) -> int:
	var sm: Dictionary = cx["str"]
	var id := int(a["id"])
	if not sm.has(id):
		sm[id] = CState.strength(a)
	return int(sm[id])


static func _hold(cx: Dictionary, st: Dictionary, f: int, a: Dictionary) -> bool:
	var h: Dictionary = cx["hold"]
	var id := int(a["id"])
	if not h.has(id):
		if cx.has("v6"):
			# Version 6: the threat is what reaches the settlement this turn.
			var r := int(a["r"])
			var thr := int(cx["thr"][r])
			h[id] = CState.owner(st, r) == f and thr > 0 and defence(st, r) - CState.strength(a) < thr
		else:
			h[id] = _must_hold(st, f, a)
		if bool(h[id]):
			# Mistakes: marching off from a threatened city (one taken last
			# turn: forgetting to garrison the conquest).
			var kn := CP.of(st, f)
			if _recent_capture(st, f, int(a["r"])):
				if _mistake(st, f, kn, CP.M_NO_GARRISON):
					h[id] = false
			elif _mistake(st, f, kn, CP.M_EMPTY_CITY):
				h[id] = false
	return bool(h[id])


## Region r was taken by f last turn (or this one).
static func _recent_capture(st: Dictionary, f: int, r: int) -> bool:
	var turn := int(st["turn"])
	for e in st["events"]:
		if str(e.get("k", "")) == "captured" and int(e.get("r", -1)) == r and int(e.get("f", -1)) == f \
				and int(e.get("turn", -100)) >= turn - 1:
			return true
	return false


## Deliberate mistake m (CP.M_*) of faction f: rolled with the state's RNG
## at the level's chance (MK_BASE + m, %); a level whose chance is 0 never
## draws (Average campaigns are unchanged). Counted (CP.MISTAKE_KEYS).
static func _mistake(st: Dictionary, f: int, kn: PackedInt32Array, m: int) -> bool:
	var p := kn[CP.MK_BASE + m]
	if p <= 0 or CState.rand(st, 100) >= p:
		return false
	CP.count(CP.MISTAKE_KEYS[m], f)
	return true


## One raid a turn: a free army marches into a rich enemy region it reaches
## this turn with no enemy field army there and none near that outmatches it.
static func _raid(st: Dictionary, f: int, free: Array, rcs: Dictionary, used: Dictionary, out: Array, cx: Dictionary) -> void:
	var best_a: Dictionary = {}
	var best_t := -1
	var best_v := 0
	var raid_w := CP.of(st, f)[CP.RAID_WEALTH]
	for a in free:
		var id := int(a["id"])
		if used.has(id) or CRules.siege_role(st, a) != 0 or _hold(cx, st, f, a):
			continue
		var rc: Dictionary = rcs[id]
		for t in CData.region_count():
			if int(rc["t"][t]) != 0:
				continue
			var o := CState.owner(st, t)
			if o < 0 or not CState.at_war(st, f, o) or int(CData.REGIONS[t]["wealth"]) < raid_w:
				continue
			if not CState.siege_at(st, t).is_empty() or not CState.battle_at(st, t).is_empty() or CRules.raider(st, t) >= 0:
				continue
			if int(cx["foe"][t]) != 0 or int(cx["thr"][t]) > _str(cx, a):
				continue
			var v := CRules.region_income(st, t)
			if v > best_v:
				best_v = v
				best_t = t
				best_a = a
	if best_t >= 0:
		used[int(best_a["id"])] = 1
		out.append([int(best_a["id"]), best_t, f, CData.MODE_MARCH, 0])


## Screens: a threatened city of ours without a field army gets the nearest
## free army that can match the threat (it stands there in the field).
static func _screen(st: Dictionary, f: int, free: Array, rcs: Dictionary, used: Dictionary, out: Array, cx: Dictionary) -> void:
	var screen_pct := CP.of(st, f)[CP.SCREEN_PCT]
	for r in CState.regions_of(st, f):
		if not CState.siege_at(st, r).is_empty() or not CState.battle_at(st, r).is_empty():
			continue
		var thr := int(cx["thr"][r])
		if thr == 0:
			continue
		var guarded := false
		for a in CState.armies_in(st, r):
			if int(a["f"]) == f and CState.stance(a) == CData.STANCE_FIELD:
				guarded = true
		if guarded:
			continue
		var best: Dictionary = {}
		for a in free:
			var id := int(a["id"])
			if used.has(id) or CRules.siege_role(st, a) != 0 or int(a["r"]) == r or int(rcs[id]["t"][r]) != 0:
				continue
			if _str(cx, a) * 100 < thr * screen_pct or _hold(cx, st, f, a):
				continue
			if best.is_empty() or _str(cx, a) > _str(cx, best):
				best = a
		if not best.is_empty():
			used[int(best["id"])] = 1
			out.append([int(best["id"]), r, f, CData.MODE_MARCH, 0])
		elif CState.armies_in(st, r).is_empty():
			CP.count(CP.C_EMPTY_CITY, f)


## Stances of the armies that stay in our regions: inside the walls when the
## enemy within a turn's march is much stronger than our armies there, in
## the field otherwise (never riding out into a battle it would lose).
static func _stances(st: Dictionary, f: int, used: Dictionary, cx: Dictionary) -> void:
	var kn := CP.of(st, f)
	for r in CState.regions_of(st, f):
		if not CState.siege_at(st, r).is_empty() or not CState.battle_at(st, r).is_empty():
			continue
		var here: Array = []
		for a in CState.armies_in(st, r):
			if int(a["f"]) == f and int(a["busy"]) == 0 and not used.has(int(a["id"])):
				here.append(a)
		if here.is_empty():
			continue
		var thr := int(cx["thr"][r])
		var want := CData.STANCE_FIELD
		if thr > 0 and _sum(here) * 100 < thr * kn[CP.SHELTER_PCT]:
			want = CData.STANCE_GARRISON
		if want == CData.STANCE_FIELD and int(cx["here"][r]) != 0:
			var od := CBattle.odds(st, here, _foes_in(st, f, r), r, false, -1)
			if int(od["win"]) < kn[CP.RELIEF_WIN]:
				want = CData.STANCE_GARRISON
		for a in here:
			if CState.stance(a) != want:
				CRules.apply_order(st, f, {"t": "stance", "a": int(a["id"]), "s": want})


static func _foes_in(st: Dictionary, f: int, r: int) -> Array:
	var out: Array = []
	for a in CState.armies_in(st, r):
		if int(a["busy"]) == 0 and CState.at_war(st, f, int(a["f"])):
			out.append(a)
	return out

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
	var kn := CP.of(st, to)
	match what:
		"peace":
			var since := CState.dip_since(st, from, to)
			if since < kn[CP.PEACE_MIN_TURNS]:
				return false
			# Accept when not clearly winning, after a long war, or when
			# down to few regions.
			return mine * 100 < theirs * kn[CP.PEACE_ACCEPT_PCT] or since >= kn[CP.PEACE_ACCEPT_LONG] \
				or CState.regions_of(st, to).size() <= kn[CP.PEACE_ACCEPT_REGIONS]
		"trade":
			return CState.dip_since(st, from, to) >= kn[CP.TRADE_ACCEPT_TURNS] and mine * 100 < theirs * kn[CP.TRADE_ACCEPT_PCT]
		"cancel_trade":
			return true
	return false


static func diplomacy(st: Dictionary, f: int) -> void:
	if not CState.alive(st, f) or CState.is_human(st, f):
		return
	var turn := int(st["turn"])
	var mine := faction_strength(st, f)
	var my_wars := wars(st, f)
	var kn := CP.of(st, f)
	if my_wars.size() >= 2:
		CP.count(CP.C_TWO_FRONTS, f)
	# Peace when losing a long war.
	for g in my_wars:
		if CState.dip_since(st, f, g) < kn[CP.PEACE_ASK_TURNS]:
			continue
		var theirs := faction_strength(st, g)
		if mine * 100 < theirs * kn[CP.PEACE_ASK_PCT] or CState.dip_since(st, f, g) >= kn[CP.PEACE_ASK_LONG]:
			_propose(st, f, g, "peace")
	if kn[CP.SK_ONE_FRONT] != 0 and my_wars.size() >= 2 and CState.grid_on(st):
		# Skilled (4.3): one front at a time: peace with every enemy but the
		# one we press hardest (the most of its regions our armies reach
		# next turn; ties: the weakest).
		_one_front(st, f, my_wars, kn)
		my_wars = wars(st, f)
	# Trade with neighbours at peace.
	for g in CState.nf():
		if g == f or not CState.alive(st, g) or CState.dip(st, f, g) != CState.PEACE:
			continue
		if CState.dip_since(st, f, g) >= kn[CP.TRADE_ASK_TURNS] and _neighbours(st, f, g) \
				and CState.rand(st, 100) < kn[CP.TRADE_ASK_CHANCE]:
			_propose(st, f, g, "trade")
	# Opportunistic war.
	if turn < kn[CP.FIRST_WAR_TURN] or my_wars.size() >= kn[CP.MAX_WARS]:
		return
	if kn[CP.MK_BASE + CP.M_UNWISE_WAR] > 0 and _unwise_war(st, f, kn, mine):
		return
	var aggr := _aggr(st)
	for g in CState.nf():
		if g == f or not CState.alive(st, g) or CState.dip(st, f, g) == CState.WAR:
			continue
		if CState.friendly(st, f, g) or not _neighbours(st, f, g) or CState.dip_since(st, f, g) < kn[CP.WAR_CALM_TURNS]:
			continue
		var theirs := faction_strength(st, g)
		# Weaker neighbours, or ones already fighting someone else.
		var busy := not wars(st, g).is_empty()
		if mine * 100 < theirs * (kn[CP.WAR_RATIO_BUSY] if busy else kn[CP.WAR_RATIO]):
			continue
		var chance := kn[CP.WAR_CHANCE] * aggr / 100
		if CState.is_human(st, g):
			var last := int(st["stats"].get("last_war_on_players", -100))
			if turn < kn[CP.FIRST_WAR_ON_PLAYERS] or turn - last < kn[CP.PLAYER_WAR_GAP]:
				continue
			chance = kn[CP.WAR_CHANCE_PLAYERS] * aggr / 100
		if CState.dip(st, f, g) == CState.TRADE:
			chance /= kn[CP.TRADE_WAR_DIV]
		# Big realms start fewer wars.
		var owned := CState.regions_of(st, f).size()
		var big := kn[CP.BIG_REALM]
		if owned > big:
			chance = chance * big / owned
		if kn[CP.SK_WAR_BORDER_PCT] > 0 and CState.grid_on(st):
			# Skilled (4.8): war when their armies are away from our border,
			# hardly ever when they stand on it.
			chance = chance * (kn[CP.SK_WAR_WEAK_PCT] if _border_weak(st, f, g, kn) else kn[CP.SK_WAR_GUARDED_PCT]) / 100
		if CState.rand(st, 100) < chance:
			CRules.declare_war(st, f, g)
			if CState.is_human(st, g):
				st["stats"]["last_war_on_players"] = turn
			return


## Skilled (4.8): g's field armies that can reach one of our settlements
## next turn are at most SK_WAR_BORDER_PCT % of our field armies that can
## reach one of g's (its armies are away from the shared border).
static func _border_weak(st: Dictionary, f: int, g: int, kn: PackedInt32Array) -> bool:
	if _sf.is_empty():
		site_dist(0, 0, false)
	var near := [0, 0]
	var sides := [f, g]
	for a in st["armies"]:
		var k := sides.find(int(a["f"]))
		if k < 0 or int(a["busy"]) != 0 or CRules.siege_role(st, a) != 0:
			continue
		var full := CState.max_mp6(_default_of(a))
		var c := CState.cell(a)
		for r in CState.regions_of(st, sides[1 - k]):
			var d: int = (_sf[r] as PackedInt32Array)[c]
			if d < CGrid.INF and d - int(_site_cost[r]) <= full:
				near[k] += CState.strength(a)
				break
	return near[1] * 100 <= near[0] * kn[CP.SK_WAR_BORDER_PCT]


## Skilled (4.3): at war on two fronts or more, propose peace to every
## enemy but the one whose regions our armies reach most (an AI accepts by
## its own rule, accepts(); a player is asked).
static func _one_front(st: Dictionary, f: int, my_wars: Array[int], kn: PackedInt32Array) -> void:
	var keep := -1
	var keep_n := -1
	var keep_s := 0
	for g in my_wars:
		var n := 0
		for r in CState.regions_of(st, g):
			for a in CState.armies_of(st, f):
				if int(a["busy"]) == 0 and eta(st, a, r) <= 1:
					n += 1
					break
		var s := faction_strength(st, g)
		if n > keep_n or (n == keep_n and s < keep_s):
			keep = g
			keep_n = n
			keep_s = s
	for g in my_wars:
		if g != keep and CState.dip_since(st, f, g) >= kn[CP.PEACE_MIN_TURNS]:
			_propose(st, f, g, "peace")


## Mistake: war on a neighbour that is stronger than the level's war ratio
## allows (the same pacing as any war: calm turns, the players' war gap).
## The candidate is found from a random start among the factions.
static func _unwise_war(st: Dictionary, f: int, kn: PackedInt32Array, mine: int) -> bool:
	var turn := int(st["turn"])
	var nf := CState.nf()
	var cands: Array[int] = []
	for g in nf:
		if g == f or not CState.alive(st, g) or CState.dip(st, f, g) == CState.WAR:
			continue
		if CState.friendly(st, f, g) or not _neighbours(st, f, g) or CState.dip_since(st, f, g) < kn[CP.WAR_CALM_TURNS]:
			continue
		if CState.is_human(st, g):
			var last := int(st["stats"].get("last_war_on_players", -100))
			if turn < kn[CP.FIRST_WAR_ON_PLAYERS] or turn - last < kn[CP.PLAYER_WAR_GAP]:
				continue
		if mine * 100 < faction_strength(st, g) * kn[CP.WAR_RATIO]:
			cands.append(g)
	if cands.is_empty() or not _mistake(st, f, kn, CP.M_UNWISE_WAR):
		return false
	var g: int = cands[CState.rand(st, cands.size())]
	CRules.declare_war(st, f, g)
	if CState.is_human(st, g):
		st["stats"]["last_war_on_players"] = turn
	return true


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


# ------------------------------------------ the continuous overworld (v6) ---

## Sea lanes in the AI's static distance fields cost this many points (a
## property of the memoised distance fields, shared by every profile).
const FIELD_SEA := 200


## Turns army a needs to reach region r's settlement (a hostile one: its
## ring) by the static distance field of that settlement (CGrid.field: no
## zones, no borders; the rules find the real path): 0 this turn, INF never.
static func eta(st: Dictionary, a: Dictionary, r: int, full: int = -1) -> int:
	if full < 0:
		full = CState.full_mp(st, a)
	var left := mini(CState.mp(a), full) if full == CState.full_mp(st, a) and int(a["moved"]) != 0 else full
	return _eta_d(site_dist(CState.cell(a), r, not CState.friendly(st, int(a["f"]), CState.owner(st, r))), full, left)


## Turns for distance d with `full` points a turn and `left` now.
static func _eta_d(d: int, full: int, left: int) -> int:
	if full <= 0 or d >= CGrid.INF:
		return CRules.INF
	if d <= left:
		return 0
	return 1 + (d - left - 1) / full


static var _sf: Array = []
static var _site_cost: Array[int] = []


## Static distance from cell c to region r's settlement (ring: next to it,
## when `ring`), from the memoised fields of every settlement.
static func site_dist(c: int, r: int, ring: bool) -> int:
	if _sf.is_empty():
		for k in CData.region_count():
			_sf.append(CGrid.field(CGrid.site(k), FIELD_SEA))
			_site_cost.append(CGrid.cost(CGrid.site(k)))
	var d: int = (_sf[r] as PackedInt32Array)[c]
	if ring and d < CGrid.INF:
		d = maxi(d - CGrid.cost(CGrid.site(r)), 0)
	return d


## The move step with the continuous overworld (state version 6). Plans
## only, as _move_free (version 5), with turns to a region from the static
## distance fields; destinations are cells: a hostile settlement (lay siege
## or storm it), an enemy army (attack it), a region's field cell (next to
## its settlement: screens, gathering, the frontier) or camp (raids, with
## the raiding stance). Then: attack enemy armies standing in our lands when
## the odds favour it; forced march to a screen or a gathering point a turn
## sooner; armies staying in a threatened region fortify, or go inside the
## walls when far outmatched; the rest default.
static func _move_grid(st: Dictionary, f: int, out: Array) -> void:
	var kn := CP.of(st, f)
	var ratio := kn[CP.ATTACK_RATIO6] * 100 / _aggr(st)
	var nreg := CData.region_count()
	var etas := {}
	var free: Array = []
	var want := {}  # army id -> stance
	var hostile: Array[bool] = []
	for r in nreg:
		hostile.append(not CState.friendly(st, f, CState.owner(st, r)))
	for a in CState.armies_of(st, f):
		if int(a["busy"]) != 0:
			continue
		CRules._drop_march(a)
		if int(a["moved"]) != 0 or CRules.siege_role(st, a) == 2:
			continue
		var full := CState.max_mp6(_default_of(a))
		var t: Array[int] = []
		var c := CState.cell(a)
		if _sf.is_empty():
			site_dist(0, 0, false)
		for r in nreg:
			var d: int = (_sf[r] as PackedInt32Array)[c]
			if d >= CGrid.INF:
				t.append(CRules.INF)
				continue
			if hostile[r]:
				d = maxi(d - _site_cost[r], 0)
			t.append(0 if d <= full else 1 + (d - full - 1) / full)
		etas[int(a["id"])] = {"t": t}
		free.append(a)
		want[int(a["id"])] = CData.ST_DEFAULT
	var cx := _context6(st, f)
	var used := {}
	_sieges_grid(st, f, ratio, free, etas, used, out, cx)
	_hunt(st, f, free, used, out, cx)
	# Attack plans.
	var targets: Array = []
	for t in nreg:
		var o := CState.owner(st, t)
		if not CState.at_war(st, f, o) or not CState.battle_at(st, t).is_empty() or not CState.siege_at(st, t).is_empty():
			continue
		var now: Array = []
		var soon: Array = []
		for a in free:
			var id := int(a["id"])
			if used.has(id) or CRules.siege_role(st, a) != 0:
				continue
			var tt := int(etas[id]["t"][t])
			if tt == 0:
				now.append(a)
			elif tt == 1:
				soon.append(a)
		if now.is_empty() and soon.is_empty():
			continue
		var d := maxi(target_defence(st, f, t), 1)
		if kn[CP.SK_REACH_DEF_PCT] > 0:
			# Skilled (4.10): the owner's field armies that can be at the
			# settlement next turn count too (strike where they are not).
			d += _reach_def(st, f, cx, t) * kn[CP.SK_REACH_DEF_PCT] / 100
		var val := region_value(st, t, f)
		if o >= 0 and CState.is_human(st, o):
			val = val * kn[CP.HUMAN_VALUE_PCT] / 100
		var score := val * 1000 / d
		if kn[CP.TARGET_NEAREST] != 0:
			score = (1 << 20 if not now.is_empty() else 0) + val  # the nearest, defence not weighed
		targets.append({"t": t, "def": d, "now": now, "soon": soon, "score": score})
	targets.sort_custom(func(x, y): return x["score"] > y["score"] or (x["score"] == y["score"] and x["t"] < y["t"]))
	for tg in targets:
		_attack6(st, f, tg, ratio, etas, used, out, cx, want)
	# Idle armies take a fair chance.
	for a in free:
		var id := int(a["id"])
		if used.has(id) or int(a.get("idle", 0)) < kn[CP.IDLE_TURNS] or CRules.siege_role(st, a) != 0 or _hold(cx, st, f, a):
			continue
		var best := -1
		var best_v := 0
		var best_win := 0
		for tg in targets:
			var t := int(tg["t"])
			if int(etas[id]["t"][t]) != 0 or not CState.siege_at(st, t).is_empty() or not CState.battle_at(st, t).is_empty():
				continue
			var od := CBattle.odds(st, [a], _defenders6(st, t), t, true)
			if int(od["win"]) >= kn[CP.IDLE_WIN] and region_value(st, t, f) > best_v:
				best_v = region_value(st, t, f)
				best = t
				best_win = int(od["win"])
		if best >= 0:
			used[id] = 1
			if best_win < 50:
				CP.count(CP.C_BAD_ODDS, f)
			_go(out, a, CGrid.site(best), f, CData.MODE_ASSAULT if kn[CP.ASSAULT_ALWAYS] != 0 else CData.MODE_SIEGE)
	if kn[CP.SK_SAFE_WIN] > 0:
		_fall_back(st, f, free, etas, used, out, cx)
	if kn[CP.STANCES] != 0:
		_raid6(st, f, free, etas, used, out, cx, want)
	_screen6(st, f, free, etas, used, out, cx, want)
	if kn[CP.SK_RALLY] > 0:
		_rally(st, f, free, used, out, cx)
	# The rest march towards the frontier.
	var dist := _frontier_dist(st, f)
	for a in free:
		var id := int(a["id"])
		if used.has(id) or CRules.siege_role(st, a) != 0:
			continue
		var r := int(a["r"])
		if (dist[r] == 0 and CState.owner(st, r) == f) or _hold(cx, st, f, a):
			continue
		var et: Array = etas[id]["t"]
		var best := -1
		for n in nreg:
			if dist[n] != 0 or int(et[n]) >= CRules.INF or not CState.siege_at(st, n).is_empty() \
					or not CState.friendly(st, f, CState.owner(st, n)) or n == r:
				continue
			if best < 0 or int(et[n]) < int(et[best]) or (int(et[n]) == int(et[best]) and n < best):
				best = n
		if best >= 0:
			used[id] = 1
			_go(out, a, _toward(st, f, a, CState.field_cell(best), cx), f, CData.MODE_SIEGE)
	if kn[CP.STANCES] != 0:
		_stances6(st, f, free, used, cx, want, out)
	for a in free:
		var id := int(a["id"])
		if CState.army_index(st, id) >= 0 and int(a["busy"]) == 0 and CState.stance(a) != int(want[id]):
			CRules.apply_order(st, f, {"t": "stance", "a": id, "s": int(want[id])})


## A copy-free view of army a at the default stance (for its full points).
static func _default_of(a: Dictionary) -> Dictionary:
	return {"units": a["units"], "stance": CData.ST_DEFAULT}


## A march toward cell dest more than a turn and a half away goes to a
## waypoint instead: about a turn down the static distance field of dest's
## region's settlement, backed off out of enemy zones and lands it may not
## enter (the AI re-plans every turn; short searches stay cheap).
static func _toward(st: Dictionary, f: int, a: Dictionary, dest: int, cx: Dictionary) -> int:
	var r := CGrid.region(dest)
	if r < 0:
		return dest
	var full := CState.max_mp6(_default_of(a))
	var fld := CGrid.field(CGrid.site(r), FIELD_SEA)
	var c := CState.cell(a)
	if fld[c] >= CGrid.INF or fld[c] - fld[dest] <= full * CP.of(st, f)[CP.TOWARD_PCT] / 100:
		return dest
	var zm: PackedInt32Array = cx["zone"] if cx.has("zone") else PackedInt32Array()
	if zm.is_empty():
		zm = CRules.zone_mask(st, f)
		cx["zone"] = zm
	var trail: Array[int] = []
	var start_d := fld[c]
	for guard in 60:
		var nx := CGrid.downhill(fld, c, FIELD_SEA)
		if nx < 0 or start_d - fld[nx] > full:
			break
		c = nx
		trail.append(c)
	for k in range(trail.size() - 1, -1, -1):
		var tc: int = trail[k]
		if zm[tc] == 0 and CGrid.site_region(tc) < 0 and CRules.can_enter(st, f, CGrid.region(tc)) == "":
			return tc
	return dest


static func _go(out: Array, a: Dictionary, c: int, f: int, mode: int, tgt: int = -1) -> void:
	out.append([int(a["id"]), c, f, mode, 0, tgt])


## Armies of region r's owner's side inside or next to its settlement.
static func _defenders6(st: Dictionary, r: int) -> Array:
	var o := CState.owner(st, r)
	var out: Array = []
	if o < 0:
		return out
	var s := CGrid.site(r)
	for a in st["armies"]:
		if CState.friendly(st, int(a["f"]), o) and CGrid.cheb(CState.cell(a), s) <= 1:
			out.append(a)
	return out


## _context for version 6: "thr" per region the strength of the enemy
## armies that reach its settlement this turn (by eta), "foe" 1 if an enemy
## army stands in the field in the region, "here" 1 if any enemy army
## stands there; "str", "hold" as in _context.
static func _context6(st: Dictionary, f: int) -> Dictionary:
	var n := CData.region_count()
	var thr: Array[int] = []
	var foe: Array[int] = []
	var here: Array[int] = []
	thr.resize(n)
	foe.resize(n)
	here.resize(n)
	thr.fill(0)
	foe.fill(0)
	here.fill(0)
	var sm := {}
	if _sf.is_empty():
		site_dist(0, 0, false)
	for a in st["armies"]:
		if int(a["busy"]) != 0 or not CState.at_war(st, f, int(a["f"])):
			continue
		var s := CState.strength(a)
		sm[int(a["id"])] = s
		var ar := int(a["r"])
		here[ar] = 1
		if not CRules.inside(st, a):
			foe[ar] = 1
		var full := CState.max_mp6(_default_of(a))
		var c := CState.cell(a)
		for r in n:
			# Within its march of the settlement (of the ring for a city of
			# ours, hostile to it): "thr" for our regions, "near" for all.
			var d: int = (_sf[r] as PackedInt32Array)[c]
			if d < CGrid.INF and d - int(_site_cost[r]) <= full:
				thr[r] += s
	return {"thr": thr, "foe": foe, "here": here, "str": sm, "hold": {}, "v6": 1}


static func _attack6(st: Dictionary, f: int, tg: Dictionary, ratio: int, _etas: Dictionary, used: Dictionary, out: Array,
		cx: Dictionary, want: Dictionary) -> void:
	var t := int(tg["t"])
	var d := int(tg["def"])
	var kn := CP.of(st, f)
	var commit := d * ratio * kn[CP.COMMIT_PCT] / 100
	var now: Array = []
	var soon: Array = []
	for a in tg["now"]:
		if not used.has(int(a["id"])) and not _hold(cx, st, f, a):
			now.append(a)
	for a in tg["soon"]:
		if not used.has(int(a["id"])) and not _hold(cx, st, f, a):
			soon.append(a)
	for a in now + soon:
		_str(cx, a)
	var sm: Dictionary = cx["str"]
	var by_strength := func(x, y): return int(sm[int(x["id"])]) > int(sm[int(y["id"])]) \
		or (int(sm[int(x["id"])]) == int(sm[int(y["id"])]) and int(x["id"]) < int(y["id"]))
	now.sort_custom(by_strength)
	soon.sort_custom(by_strength)
	var p_now := 0
	var p_soon := 0
	for a in now:
		p_now += _str(cx, a)
	for a in soon:
		p_soon += _str(cx, a)
	var site := CGrid.site(t)
	if p_now * 100 >= d * ratio:
		var sent := 0
		var n_sent := 0
		for a in now:
			used[int(a["id"])] = 1
			_go(out, a, site, f, CData.MODE_ASSAULT)
			sent += _str(cx, a)
			n_sent += 1
			if sent * 100 >= commit:
				break
		if n_sent == 1 and not soon.is_empty():
			CP.count(CP.C_TRICKLED, f)
		if n_sent >= 2 and kn[CP.SK_SUPPORT] != 0:
			CP.count(CP.C_SK_TIMED, f)  # Skilled: two armies or more strike together
		return
	var lay := CData.MODE_ASSAULT if kn[CP.ASSAULT_ALWAYS] != 0 else CData.MODE_SIEGE
	if p_now * 100 >= d * ratio * kn[CP.SIEGE_RATIO_PCT] / 100 and not now.is_empty() and (not soon.is_empty() or now.size() > 1):
		for a in now:
			used[int(a["id"])] = 1
			_go(out, a, site, f, lay)
		return
	# Mistake: attacking at poor odds with what is there (one roll a turn).
	if not now.is_empty() and not cx.has("mk_odds") and kn[CP.MK_BASE + CP.M_BAD_ODDS] > 0:
		cx["mk_odds"] = 1
		if _mistake(st, f, kn, CP.M_BAD_ODDS):
			CP.count(CP.C_BAD_ODDS, f)
			for a in now:
				used[int(a["id"])] = 1
				_go(out, a, site, f, CData.MODE_ASSAULT)
			return
	if soon.is_empty() or (p_now + p_soon) * 100 < d * ratio:
		return
	if kn[CP.GATHER] == 0:
		# No gathering: the armies go as they are, arriving a turn apart.
		if not now.is_empty():
			CP.count(CP.C_TRICKLED, f)
		for a in now + soon:
			used[int(a["id"])] = 1
			_go(out, a, site, f, CData.MODE_ASSAULT)
		return
	# Concentrate: gather within support range of each other a march short
	# of the target, on the way the strongest of them would come (down the
	# target's distance field, backed off out of enemy zones); attack next
	# turn.
	var all: Array = now + soon
	var lead: Dictionary = all[0]
	var fld := CGrid.field(site, FIELD_SEA)
	var full := CState.max_mp6(_default_of(lead))
	var zm: PackedInt32Array = cx["zone"] if cx.has("zone") else PackedInt32Array()
	if zm.is_empty():
		zm = CRules.zone_mask(st, f)
		cx["zone"] = zm
	var trail: Array[int] = [CState.cell(lead)]
	var c := CState.cell(lead)
	for guard in 200:
		if fld[c] <= full * kn[CP.GATHER_PCT] / 100:
			break
		var nx := CGrid.downhill(fld, c, FIELD_SEA)
		if nx < 0:
			break
		c = nx
		trail.append(c)
	var sc := -1
	var foes: Array = []
	var gskip := {}
	if kn[CP.SK_STAGE_SAFE] > 0:
		foes = _foes6(st, f)
		for a in all:
			gskip[int(a["id"])] = 1
	for k in range(trail.size() - 1, -1, -1):
		var tc: int = trail[k]
		if zm[tc] == 0 and CGrid.site_region(tc) < 0 and CRules.can_enter(st, f, CGrid.region(tc)) == "":
			# Skilled (4.4): not where the enemy can fall on the gathering
			# armies next turn at SK_STAGE_SAFE % (further back instead).
			if kn[CP.SK_STAGE_SAFE] > 0 and k > 0 and _danger(st, f, tc, p_now + p_soon, foes, gskip, kn) >= kn[CP.SK_STAGE_SAFE]:
				continue
			sc = tc
			break
	if sc < 0:
		return
	var sent2 := 0
	for a in all:
		var id := int(a["id"])
		used[id] = 1
		if CGrid.cheb(CState.cell(a), sc) > 1:
			var dist := maxi(fld[CState.cell(a)] - fld[sc], 0)
			if dist > CState.max_mp6(_default_of(a)) and dist <= CState.max_mp6({"units": a["units"], "stance": CData.ST_FORCED}) \
					and CState.friendly(st, f, CState.owner(st, int(a["r"]))):
				want[id] = CData.ST_FORCED  # a turn sooner on a forced march
			_go(out, a, sc, f, CData.MODE_SIEGE)
		sent2 += _str(cx, a)
		if sent2 * 100 >= commit:
			break


## Version 6 sieges (as _sieges_free; armies that reach the ring this turn).
static func _sieges_grid(st: Dictionary, f: int, ratio: int, free: Array, etas: Dictionary, used: Dictionary, out: Array,
		cx: Dictionary) -> void:
	for sg in (st["sieges"] as Array).duplicate():
		var r := int(sg["r"])
		if CState.siege_at(st, r).is_empty() or not CState.battle_at(st, r).is_empty():
			continue
		var o := CState.owner(st, r)
		var site := CGrid.site(r)
		if int(sg["f"]) == f:
			var bs := CRules.besiegers(st, r)
			var join: Array = []
			for a in free:
				var id := int(a["id"])
				if not used.has(id) and CRules.siege_role(st, a) == 0 and int(etas[id]["t"][r]) == 0 and not _hold(cx, st, f, a):
					join.append(a)
			var od := CBattle.odds(st, bs + join, CRules.besieged_armies(st, r), r, true)
			var relief := _relief_near6(st, f, r)
			var starving := int(sg["supply"]) <= 0
			var storm := int(od["att"]) * 100 >= int(od["def"]) * ratio or (starving and not relief.is_empty())
			var kn := CP.of(st, f)
			if not storm and kn[CP.SK_STORM_RELIEF_WIN] > 0 and int(od["win"]) >= kn[CP.SK_STORM_RELIEF_WIN] \
					and _relief_soon(st, f, r):
				# Skilled (4.6): storm before a relief that arrives next turn.
				storm = true
				CP.count(CP.C_SK_STORM_RELIEF, f)
			var lift := false
			if not storm and not relief.is_empty() and _sum(relief) > _sum(bs + join):
				var ro := CBattle.odds(st, relief + CRules.besieged_armies(st, r), bs + join, r, false, 0)
				lift = int(ro["win"]) >= kn[CP.LIFT_WIN]
			if not storm and not lift and int(sg["held"]) >= CState.siege_supply(st, r) + kn[CP.SIEGE_PATIENCE]:
				storm = int(od["win"]) >= kn[CP.SIEGE_ASSAULT_WIN]
				lift = not storm
				if storm and int(od["win"]) < 50:
					CP.count(CP.C_BAD_ODDS, f)
			if lift:
				for a in bs:
					if int(a["f"]) != f or int(a["busy"]) != 0 or int(a["moved"]) != 0 or not etas.has(int(a["id"])):
						continue
					var back := _way_home6(st, f, a, sg, etas[int(a["id"])])
					if back >= 0:
						used[int(a["id"])] = 1
						_go(out, a, _toward(st, f, a, CState.field_cell(back), cx), f, CData.MODE_SIEGE)
				continue
			for a in join:
				used[int(a["id"])] = 1
				_go(out, a, site, f, CData.MODE_ASSAULT if storm else CData.MODE_SIEGE)
			for a in bs:
				used[int(a["id"])] = 1
			if storm and join.is_empty():
				CRules.order_assault(st, f, r)
		elif o == f:
			var bs2 := CRules.besiegers(st, r)
			var inside := CRules.besieged_armies(st, r)
			var so := CBattle.odds(st, inside, bs2, r, false, 0)
			if not inside.is_empty() and int(so["att"]) * 100 >= int(so["def"]) * ratio:
				CRules.order_sally(st, f, r)
				continue
			var rel: Array = []
			for a in free:
				if CP.of(st, f)[CP.RELIEVE] == 0:
					break  # never relieves
				var id := int(a["id"])
				if not used.has(id) and CRules.siege_role(st, a) == 0 and int(etas[id]["t"][r]) == 0 \
						and CState.stance(a) != CData.ST_FORCED:
					rel.append(a)
			if rel.is_empty():
				continue
			var ro2 := CBattle.odds(st, rel + inside, bs2, r, false, 0)
			if int(ro2["win"]) >= CP.of(st, f)[CP.RELIEF_WIN]:
				for a in rel:
					used[int(a["id"])] = 1
					_go(out, a, site, f, CData.MODE_SIEGE)


## Armies of region r's owner's side (at war with f) near r: in the field
## within reach of its settlement this turn.
static func _relief_near6(st: Dictionary, f: int, r: int) -> Array:
	var o := CState.owner(st, r)
	var out: Array = []
	if o < 0:
		return out
	for a in st["armies"]:
		if CState.friendly(st, int(a["f"]), o) and CState.at_war(st, f, int(a["f"])) and int(a["busy"]) == 0 \
				and CRules.siege_role(st, a) == 0 and not CRules.inside(st, a) and eta(st, a, r) == 0:
			out.append(a)
	return out


static func _way_home6(st: Dictionary, f: int, a: Dictionary, sg: Dictionary, et: Dictionary) -> int:
	var o := CRules._siege_origin(sg, int(a["id"]))
	if o >= 0 and CState.friendly(st, f, CState.owner(st, o)) and CState.siege_at(st, o).is_empty() \
			and int(et["t"][o]) < CRules.INF:
		return o
	var best := -1
	for n in CData.region_count():
		if not CState.friendly(st, f, CState.owner(st, n)) or not CState.siege_at(st, n).is_empty() or int(et["t"][n]) >= CRules.INF:
			continue
		if best < 0 or int(et["t"][n]) < int(et["t"][best]) or (int(et["t"][n]) == int(et["t"][best]) and n < best):
			best = n
	return best


## Enemy armies in the field are attacked by the free armies that reach
## them this turn (an estimate: HUNT_COST points a cell on the straight
## line) when those armies' odds reach HUNT_WIN % (RELIEF_WIN % in our own
## lands); nearest first.
static func _hunt(st: Dictionary, f: int, free: Array, used: Dictionary, out: Array, cx: Dictionary) -> void:
	var kn := CP.of(st, f)
	var hunt_cost := kn[CP.HUNT_COST]
	var hunt_slack := kn[CP.HUNT_SLACK]
	for e in st["armies"]:
		if int(e["busy"]) != 0 or not CState.at_war(st, f, int(e["f"])) or CRules.inside(st, e) or CRules.siege_role(st, e) == 2:
			continue
		var ec := CState.cell(e)
		var go: Array = []
		for a in free:
			var id := int(a["id"])
			if used.has(id) or CRules.siege_role(st, a) != 0 or _hold(cx, st, f, a):
				continue
			if int(CData.REGIONS[int(a["r"])]["land"]) != int(CData.REGIONS[int(e["r"])]["land"]):
				continue  # not across the sea
			if CGrid.octile(CState.cell(a), ec) * hunt_cost / 10 + hunt_slack <= CState.max_mp6(_default_of(a)):
				go.append(a)
		if go.is_empty():
			continue
		var od := CBattle.odds(st, go, [e], int(e["r"]), false, -1)
		var need := kn[CP.RELIEF_WIN] if CState.owner(st, int(e["r"])) == f else kn[CP.HUNT_WIN]
		if kn[CP.SK_SUPPORT] != 0:
			# Skilled: the target's friends within support range of its cell
			# join the battle (the rules' _support6): count them.
			var alone_win := int(od["win"])
			od = CBattle.odds(st, go, [e] + _supporters(st, f, e), int(e["r"]), false, -1)
			if kn[CP.SK_HUNT_WIN] > 0 and CState.owner(st, int(e["r"])) != f:
				need = kn[CP.SK_HUNT_WIN]
			var relief := _relief_of_ours(st, f, e)
			if relief and kn[CP.SK_INTERCEPT_WIN] > 0:
				need = mini(need, kn[CP.SK_INTERCEPT_WIN])  # 4.6: intercept the relief in the field
			if int(od["win"]) < need:
				if alone_win >= need:
					CP.count(CP.C_SK_HUNT_DECLINED, f)
				continue
			if int(od["att"]) >= 2 * int(od["def"]):
				CP.count(CP.C_SK_TWO_TO_ONE, f)
			if relief:
				CP.count(CP.C_SK_INTERCEPT, f)
		if int(od["win"]) < need:
			continue
		for a in go:
			used[int(a["id"])] = 1
			_go(out, a, ec, f, CData.MODE_SIEGE, int(e["id"]))


## Skilled: the armies of e's side (at war with f) that would join a battle
## on e's cell as support (the rules' _support6: in the field, not in a
## battle or a siege, not on a forced march, within their support radius).
static func _supporters(st: Dictionary, f: int, e: Dictionary) -> Array:
	var out: Array = []
	var ec := CState.cell(e)
	var ef := int(e["f"])
	for d in st["armies"]:
		if int(d["id"]) == int(e["id"]) or int(d["busy"]) != 0 or not CState.friendly(st, int(d["f"]), ef) \
				or not CState.at_war(st, f, int(d["f"])):
			continue
		if absi(int(d["x"]) - CGrid.cx(ec)) > CData.SUPPORT + 2 or absi(int(d["y"]) - CGrid.cy(ec)) > CData.SUPPORT + 2:
			continue
		if CState.stance(d) == CData.ST_FORCED or CRules.inside(st, d) or CRules.siege_role(st, d) != 0:
			continue
		if CGrid.within(ec, CState.cell(d), CRules.support_r(d)):
			out.append(d)
	return out


## Skilled: enemy army e can reach, within a turn, a city of its side that
## our side besieges (a relief).
static func _relief_of_ours(st: Dictionary, f: int, e: Dictionary) -> bool:
	for sg in st["sieges"]:
		var r := int(sg["r"])
		if CState.friendly(st, f, int(sg["f"])) and CState.friendly(st, int(e["f"]), CState.owner(st, r)) and eta(st, e, r) <= 1:
			return true
	return false


## Skilled (4.10): strength of the field armies of region t's owner's side
## (at war with f, not in region t: those are in its defence) that reach
## t's settlement within a turn by the static distance fields; per region,
## computed once a turn (cx "rdef").
static func _reach_def(st: Dictionary, f: int, cx: Dictionary, t: int) -> int:
	if not cx.has("rdef"):
		var n := CData.region_count()
		var by_f: Array = []  # per faction g: per region, strength of g's armies reaching it
		for g in CState.nf():
			var row: Array[int] = []
			row.resize(n)
			row.fill(0)
			by_f.append(row)
		for e in st["armies"]:
			var g := int(e["f"])
			if int(e["busy"]) != 0 or not CState.at_war(st, f, g) or CRules.inside(st, e) or CRules.siege_role(st, e) != 0:
				continue
			var s := CState.strength(e)
			var full := CState.max_mp6(_default_of(e))
			var c := CState.cell(e)
			var row: Array[int] = by_f[g]
			for r in n:
				if r == int(e["r"]):
					continue
				var dd: int = (_sf[r] as PackedInt32Array)[c]
				if dd < CGrid.INF and dd - int(_site_cost[r]) <= full:
					row[r] += s
		cx["rdef"] = by_f
	var o := CState.owner(st, t)
	if o < 0:
		return 0
	var out := 0
	for g in CState.nf():
		if CState.friendly(st, g, o) and CState.at_war(st, f, g):
			out += int((cx["rdef"][g] as Array)[t])
	return out


## Skilled (4.9, 4.10): the enemy armies (at war with f, in the field) as
## [cell, strength, points a turn, land] for _danger: where they can strike
## next turn, by the same estimate the hunters use.
static func _foes6(st: Dictionary, f: int) -> Array:
	var out: Array = []
	for e in st["armies"]:
		if int(e["busy"]) != 0 or not CState.at_war(st, f, int(e["f"])) or CRules.siege_role(st, e) == 2:
			continue
		out.append([CState.cell(e), CState.strength(e), CState.max_mp6(_default_of(e)), int(CData.REGIONS[int(e["r"])]["land"])])
	return out


## Skilled: the attacker's chance (%) if every enemy army that can reach cell
## c next turn attacked an army of ours standing there with strength `mine`
## (its stance counted), joined by our armies within support range of c
## (not those in `skip`: ids). 0 when no enemy reaches it.
static func _danger(st: Dictionary, f: int, c: int, mine: int, foes: Array, skip: Dictionary, kn: PackedInt32Array) -> int:
	var land := int(CData.REGIONS[CGrid.region(c)]["land"]) if CGrid.region(c) >= 0 else -1
	var att := 0
	for e in foes:
		if int(e[3]) == land and CGrid.octile(int(e[0]), c) * kn[CP.HUNT_COST] / 10 + kn[CP.HUNT_SLACK] <= int(e[2]):
			att += int(e[1])
	if att == 0:
		return 0
	var def := mine
	for a in CState.armies_of(st, f):
		if skip.has(int(a["id"])) or int(a["busy"]) != 0 or CRules.inside(st, a) or CRules.siege_role(st, a) != 0 \
				or CState.stance(a) == CData.ST_FORCED:
			continue
		if CGrid.within(c, CState.cell(a), CRules.support_r(a)):
			def += CState.strength(a) * CBattle._stance_pct(a, true) / 100
	return int(CBattle.odds_of(att, def)["win"])


## Skilled: free armies the enemy could attack next turn at SK_SAFE_WIN %
## or better fall back, this turn, to where the odds are lowest: a friendly
## region's field cell or one of our armies (support), among those they
## reach this turn. Armies holding a threatened city stay (SK_SAFE_HOLD 0)
## or fall back too (1).
static func _fall_back(st: Dictionary, f: int, free: Array, etas: Dictionary, used: Dictionary, out: Array, cx: Dictionary) -> void:
	var kn := CP.of(st, f)
	var foes := _foes6(st, f)
	if foes.is_empty():
		return
	for a in free:
		var id := int(a["id"])
		if used.has(id) or CRules.siege_role(st, a) != 0 or CRules.inside(st, a):
			continue
		if kn[CP.SK_SAFE_HOLD] == 0 and _hold(cx, st, f, a):
			continue
		var skip := {id: 1}
		var s := _str(cx, a)
		var now := _danger(st, f, CState.cell(a), s * CBattle._stance_pct(a, true) / 100, foes, skip, kn)
		if now < kn[CP.SK_SAFE_WIN]:
			continue
		var full := CState.max_mp6(_default_of(a))
		var best := -1
		var best_w := now
		var cands: Array[int] = []
		var et: Array = etas[id]["t"]
		for r in CData.region_count():
			if int(et[r]) == 0 and CState.friendly(st, f, CState.owner(st, r)) and CState.siege_at(st, r).is_empty():
				cands.append(CState.field_cell(r))
		for b in CState.armies_of(st, f):
			if int(b["id"]) != id and int(b["busy"]) == 0 and not CRules.inside(st, b) \
					and CGrid.octile(CState.cell(a), CState.cell(b)) * kn[CP.HUNT_COST] / 10 <= full:
				cands.append(CState.cell(b))
		var zm: PackedInt32Array = cx["zone"] if cx.has("zone") else PackedInt32Array()
		if zm.is_empty():
			zm = CRules.zone_mask(st, f)
			cx["zone"] = zm
		for c in cands:
			if zm[c] != 0:
				continue
			var w := _danger(st, f, c, s, foes, skip, kn)
			if w < best_w:
				best_w = w
				best = c
		if best < 0 or best_w + kn[CP.SK_SAFE_GAIN] > now:
			continue
		used[id] = 1
		CP.count(CP.C_SK_FALLBACK, f)
		_go(out, a, best, f, CData.MODE_SIEGE)


## Skilled: an army of the owner's side of besieged region r (at war with
## f, in the field) reaches its settlement within a turn.
static func _relief_soon(st: Dictionary, f: int, r: int) -> bool:
	var o := CState.owner(st, r)
	if o < 0:
		return false
	for a in st["armies"]:
		if CState.friendly(st, int(a["f"]), o) and CState.at_war(st, f, int(a["f"])) and int(a["busy"]) == 0 \
				and CRules.siege_role(st, a) == 0 and not CRules.inside(st, a) and eta(st, a, r) <= 1:
			return true
	return false


## Skilled (4.2): the preferred mix weighted toward what beats the enemies'
## armies (at war): spears (or pikes) against cavalry-heavy enemies,
## missiles against light foot. Lines the faction does not field are not
## added.
static func _counter_mix(st: Dictionary, f: int, mix: Dictionary, kn: PackedInt32Array) -> Dictionary:
	var n := 0
	var cav := 0
	var light := 0
	for a in st["armies"]:
		if not CState.at_war(st, f, int(a["f"])):
			continue
		for u in a["units"]:
			var line := UT.line_of(CState.unit_type(u))
			n += 1
			if line == "cav":
				cav += 1
			elif line == "light":
				light += 1
	if n == 0:
		return mix
	var out := mix.duplicate()
	if cav * 100 >= n * kn[CP.SK_COUNTER_SHARE]:
		for line in ["spear", "pike"]:
			if out.has(line):
				out[line] = int(out[line]) + kn[CP.SK_COUNTER_MIX]
				break
	if light * 100 >= n * kn[CP.SK_COUNTER_SHARE]:
		for line in ["archer", "javelin"]:
			if out.has(line):
				out[line] = int(out[line]) + kn[CP.SK_COUNTER_MIX] / 2
	return out


## Skilled: the spare armies (nothing else to do this turn) gather on our
## strongest army when they reach it within SK_RALLY turns: they march to
## merge into it while the two fit in one army, else to stand by it (within
## support range). Our strongest army: not in a battle or a siege.
static func _rally(st: Dictionary, f: int, free: Array, used: Dictionary, out: Array, cx: Dictionary) -> void:
	var kn := CP.of(st, f)
	var main: Dictionary = {}
	for a in CState.armies_of(st, f):
		if int(a["busy"]) != 0 or CRules.siege_role(st, a) != 0:
			continue
		if main.is_empty() or _str(cx, a) > _str(cx, main):
			main = a
	if main.is_empty():
		return
	var mid := int(main["id"])
	var mc := CState.cell(main)
	var room := CData.ARMY_MAX - CState.unit_count(main) - CRules.queued_into(st, mid)
	for a in free:
		var id := int(a["id"])
		if id == mid or used.has(id) or CRules.siege_role(st, a) != 0 or _hold(cx, st, f, a):
			continue
		var c := CState.cell(a)
		if int(CData.REGIONS[int(a["r"])]["land"]) != int(CData.REGIONS[int(main["r"])]["land"]):
			continue
		var full := CState.max_mp6(_default_of(a))
		if CGrid.octile(c, mc) * kn[CP.HUNT_COST] / 10 > kn[CP.SK_RALLY] * full:
			continue
		if CState.unit_count(a) <= room:
			room -= CState.unit_count(a)
			used[id] = 1
			CP.count(CP.C_SK_MERGE, f)
			out.append([id, mc, f, CData.MODE_SIEGE, 0, -1, mid])
		elif CGrid.within(mc, c, CData.SUPPORT - 1):
			used[id] = 1  # already standing by it
		else:
			used[id] = 1
			CP.count(CP.C_SK_RALLY, f)
			_go(out, a, _toward(st, f, a, mc, cx), f, CData.MODE_SIEGE)


## One raid a turn: a free army marches to the camp of a rich enemy region
## it reaches this turn (no enemy army there, none near that outmatches
## it) in the raiding stance.
static func _raid6(st: Dictionary, f: int, free: Array, etas: Dictionary, used: Dictionary, out: Array, cx: Dictionary,
		want: Dictionary) -> void:
	var best_a: Dictionary = {}
	var best_t := -1
	var best_v := 0
	var raid_w := CP.of(st, f)[CP.RAID_WEALTH]
	for a in free:
		var id := int(a["id"])
		if used.has(id) or CRules.siege_role(st, a) != 0 or _hold(cx, st, f, a):
			continue
		var et: Array = etas[id]["t"]
		for t in CData.region_count():
			if int(et[t]) != 0:
				continue
			var o := CState.owner(st, t)
			if o < 0 or not CState.at_war(st, f, o) or int(CData.REGIONS[t]["wealth"]) < raid_w:
				continue
			if not CState.siege_at(st, t).is_empty() or not CState.battle_at(st, t).is_empty() or CRules.raider(st, t) >= 0:
				continue
			if int(cx["foe"][t]) != 0 or int(cx["thr"][t]) > _str(cx, a):
				continue
			var v := CRules.region_income(st, t)
			if v > best_v:
				best_v = v
				best_t = t
				best_a = a
	if best_t >= 0:
		used[int(best_a["id"])] = 1
		want[int(best_a["id"])] = CData.ST_RAID
		_go(out, best_a, CGrid.camp(best_t), f, CData.MODE_SIEGE)
	# Raiders already in place keep raiding while it is safe.
	for a in free:
		var id := int(a["id"])
		if used.has(id) or CState.stance(a) != CData.ST_RAID:
			continue
		var r := int(a["r"])
		var o := CState.owner(st, r)
		if o >= 0 and CState.at_war(st, f, o) and CState.siege_at(st, r).is_empty() and int(cx["thr"][r]) <= _str(cx, a):
			used[id] = 1
			want[id] = CData.ST_RAID


## Screens: a threatened city of ours without a field army next to it gets
## the strongest free army that can match SCREEN_PCT of the threat; it
## stands in the field next to the city (its zone covers the approaches),
## on a forced march if that brings it there this turn.
static func _screen6(st: Dictionary, f: int, free: Array, etas: Dictionary, used: Dictionary, out: Array, cx: Dictionary,
		want: Dictionary) -> void:
	var kn := CP.of(st, f)
	var screen_pct := kn[CP.SCREEN_PCT]
	var near := kn[CP.SCREEN_NEAR]
	for r in CState.regions_of(st, f):
		if not CState.siege_at(st, r).is_empty() or not CState.battle_at(st, r).is_empty():
			continue
		var thr := int(cx["thr"][r])
		if thr == 0:
			continue
		var site := CGrid.site(r)
		var guarded := false
		for a in st["armies"]:
			if int(a["f"]) == f and not CRules.inside(st, a) and CGrid.cheb(CState.cell(a), site) <= near:
				guarded = true
		if guarded:
			continue
		var best: Dictionary = {}
		var forced := false
		for a in free:
			if kn[CP.SCREENS] == 0:
				break  # no screens at this level
			var id := int(a["id"])
			if used.has(id) or CRules.siege_role(st, a) != 0 or _str(cx, a) * 100 < thr * screen_pct or _hold(cx, st, f, a):
				continue
			var tt := int(etas[id]["t"][r])
			var fz := false
			if tt != 0:
				if tt == kn[CP.FORCED_HELP] and eta(st, a, r, CState.max_mp6({"units": a["units"], "stance": CData.ST_FORCED})) == 0:
					fz = true
				else:
					continue
			if best.is_empty() or _str(cx, a) > _str(cx, best):
				best = a
				forced = fz
		if not best.is_empty():
			used[int(best["id"])] = 1
			if forced:
				want[int(best["id"])] = CData.ST_FORCED
			_go(out, best, CState.field_cell(r), f, CData.MODE_SIEGE)
		elif CState.armies_in(st, r).is_empty():
			CP.count(CP.C_EMPTY_CITY, f)


## Stances of the armies that stay: in a threatened region of ours, inside
## the walls when far outmatched (they march onto the settlement), else
## fortified; elsewhere the default.
static func _stances6(st: Dictionary, f: int, free: Array, used: Dictionary, cx: Dictionary, want: Dictionary, out: Array) -> void:
	var shelter := CP.of(st, f)[CP.SHELTER_PCT]
	for a in free:
		var id := int(a["id"])
		if used.has(id) or CRules.siege_role(st, a) != 0:
			continue
		var r := int(a["r"])
		if CState.owner(st, r) != f:
			continue
		var thr := int(cx["thr"][r])
		if thr == 0:
			continue
		var mine := 0
		for b in free:
			if int(b["r"]) == r and not used.has(int(b["id"])):
				mine += _str(cx, b)
		if mine * 100 < thr * shelter and not CRules.inside(st, a):
			used[id] = 1
			_go(out, a, CGrid.site(r), f, CData.MODE_SIEGE)  # into the walls
			continue
		want[id] = CData.ST_FORTIFY if not CRules.inside(st, a) else CData.ST_DEFAULT
