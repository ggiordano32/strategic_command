extends RefCounted
## Campaign rules that change the state: player orders (validation and
## effect), movement and battle creation, applying a battle's outcome, the
## end-of-turn economy, growth, elimination and victory. The turn pipeline
## that calls these (and the AI) is cturn.gd.
##
## Orders are plain data (string keys, int values), the exact data a client
## submits for its faction (milestone 4 sends them over the network):
##   {"t": "move", "army": id, "to": region, "mode": 0 | 1}
##        (mode, state version 4: into a hostile region 0 lays siege (the
##        default when missing), 1 assaults at once; see "Sieges" below)
##        (version 5: "to" is the destination, any region the army can
##        reach; the path is computed at resolution and walked as far as the
##        army's movement points allow; mode 2 marches in without attacking
##        (raiding); mode 0 / 1 lay siege / assault on arrival; "persist" 1
##        keeps marching on later turns: the army stores dest and mode)
##   {"t": "assault", "r": region}  (version 4: the besiegers storm it;
##        version 5 also from inside the region without a siege)
##   {"t": "sally", "r": region}    (version 4: the besieged ride out)
##   {"t": "siege", "r": region}    (version 5: lay siege from inside)
##   {"t": "stance", "a": army id, "s": 0 field | 1 inside the walls} (v5)
##   {"t": "cancel_move", "army": id}  (version 5: forget a stored dest)
##   {"t": "recruit", "r": region, "unit": unit type key}
##   {"t": "build", "r": region, "chain": building chain index}
##   {"t": "merge", "army": id, "into": id}             (same region)
##   {"t": "split", "army": id, "units": [unit indices], "new": new army id}
##   {"t": "disband", "army": id, "units": [unit indices]}
##   {"t": "propose", "to": faction, "what": "peace" | "trade" | "cancel_trade"}
##   {"t": "war", "to": faction}                        (declare war)
##   {"t": "answer", "id": proposal id, "accept": 0 | 1}
## A new army id from a split is the faction's next id: f * 100000 +
## factions[f].next_army, so it does not depend on the other player's orders.
## Invalid orders are skipped (with a reason) and never stop a turn.
##
## Pending battle (state "battles"): {id, r, turn, att [army ids], def [army
## ids], att_f, def_f (region owner, -1 independent), reinf [army ids that
## joined from neighbouring regions], settlement 1 | 0}; version 4 adds
## "from" [[army id, region it came from]...] for the armies that moved in
## (where they retreat to) and, for battles of a siege, "kind": "assault"
## (settlement battle, all besiegers attack), "sally" or "relief" (field
## battles, settlement 0: the besiegers are the attackers "att", the owner's
## side "def": the garrison and the armies inside, plus the relieving army).
## The garrison of the region always fights on the owner's side.
##
## Sieges (state version 4, CState.sieges_on): a move into a hostile region
## with mode 0 camps outside its settlement (a siege record, no battle).
## Armies of the besieger's side that move in later join the siege; the
## besiegers stay until ordered away (leaving with the last one lifts it),
## cannot merge, split or disband, and storm the settlement with an
## "assault" order (or a move in with mode 1). The owner's armies inside
## cannot leave except by a "sally" (a field battle); an army of the owner's
## side moving in relieves it (a field battle with the garrison and the
## armies inside on its side). A besieged settlement yields no income,
## recruits nothing, pauses its construction and growth, and lives on its
## supplies (CState.siege_supply turns), then starves (end_of_turn) and
## surrenders when its garrison is gone and no army of the owner is inside.
##
## Battle outcome (input to apply_outcome; built by cbattle.gd from the
## battle sim's result() or from the formula): {winner: 0 attacker / 1
## defender (a draw counts as 1), mode: "fought" | "auto" | "formula",
## units: [{army, unit, killed, routed, withdrawn, remaining}] (army -1 =
## garrison, unit = index in the garrison list), garrison_pct: garrison
## strength left (%)}.

const CData := preload("res://campaign/cdata.gd")
const CState := preload("res://campaign/cstate.gd")
const UT := preload("res://sim/unit_types.gd")


# --------------------------------------------------------------- orders ---

static func new_army_id(st: Dictionary, f: int) -> int:
	return f * 100000 + int(st["factions"][f]["next_army"])


## Validate and apply one order of faction f. "move", "assault" and "sally"
## orders are only validated (the caller executes them after all other
## orders: order_assault, order_sally). Returns "" on success, else the
## reason the order was refused.
static func apply_order(st: Dictionary, f: int, o: Dictionary) -> String:
	var t := str(o.get("t", ""))
	match t:
		"move":
			return can_move(st, CState.army(st, int(o.get("army", -1))), int(o.get("to", -1)), f)
		"build":
			return _build(st, f, int(o.get("r", -1)), int(o.get("chain", -1)))
		"recruit":
			return _recruit(st, f, int(o.get("r", -1)), str(o.get("unit", "")))
		"merge":
			return _merge(st, f, int(o.get("army", -1)), int(o.get("into", -1)))
		"split":
			return _split(st, f, int(o.get("army", -1)), o.get("units", []), int(o.get("new", -1)))
		"disband":
			return _disband(st, f, int(o.get("army", -1)), o.get("units", []))
		"propose":
			return check_proposal(st, f, int(o.get("to", -1)), str(o.get("what", "")))
		"war":
			return _declare_war(st, f, int(o.get("to", -1)))
		"answer":
			return _answer(st, f, int(o.get("id", -1)), int(o.get("accept", 0)))
		"assault":
			return can_assault(st, f, int(o.get("r", -1)))
		"sally":
			return can_sally(st, f, int(o.get("r", -1)))
		"siege":
			return can_siege(st, f, int(o.get("r", -1)))
		"stance":
			return _set_stance(st, f, int(o.get("a", -1)), int(o.get("s", 0)))
		"cancel_move":
			return _cancel_move(st, f, int(o.get("army", -1)))
	return "unknown order"


## Cost of a building's next level in region r ({} if it cannot be built:
## then "why" says why).
static func build_info(st: Dictionary, f: int, r: int, c: int) -> Dictionary:
	if r < 0 or r >= CData.region_count() or c < 0 or c >= CData.CHAINS.size():
		return {"why": "bad order"}
	var rs: Dictionary = st["regions"][r]
	if int(rs["owner"]) != f:
		return {"why": "not your region"}
	var ch: Dictionary = CData.CHAINS[c]
	var cur := CState.building(st, r, c)
	var nxt := cur + 1
	if nxt > int(ch["levels"]):
		return {"why": "fully built", "max": 1}
	if nxt > int(rs["level"]) + 1:
		return {"why": "needs a %s" % CData.LEVEL_NAMES[nxt - 1].to_lower(), "level": nxt}
	if not CState.siege_at(st, r).is_empty():
		return {"why": "besieged", "level": nxt}
	if not (rs["build"] as Array).is_empty():
		return {"why": "already building", "level": nxt}
	if cur == 0 and (rs["slots"] as Array).size() >= CState.slot_count(r, int(rs["level"])):
		return {"why": "no free slot", "level": nxt}
	var cost := int(ch["cost"][nxt - 1])
	var info := {"level": nxt, "cost": cost, "turns": int(ch["turns"][nxt - 1])}
	if cost > int(st["factions"][f]["treasury"]):
		info["why"] = "not enough money"
	return info


static func _build(st: Dictionary, f: int, r: int, c: int) -> String:
	var info := build_info(st, f, r, c)
	if info.has("why"):
		return str(info["why"])
	st["factions"][f]["treasury"] = int(st["factions"][f]["treasury"]) - int(info["cost"])
	st["regions"][r]["build"] = [c, int(info["level"]), int(info["turns"])]
	return ""


## Unit types faction f can recruit in region r: Array of {t, line, tier,
## price, ok, why}. Lines in CData.LINE_ORDER, best tier first.
static func recruit_options(st: Dictionary, f: int, r: int) -> Array:
	var out: Array = []
	var ro: Dictionary = CData.roster(f)
	for line in CData.LINE_ORDER:
		if not ro.has(line):
			continue
		var tiers: Array = ro[line]
		for k in range(tiers.size() - 1, -1, -1):
			var key := str(tiers[k])
			if key == "":
				continue
			var ty := UT.index_of(key)
			var why := recruit_check(st, f, r, key)
			out.append({"t": key, "line": line, "tier": k + 1, "price": UT.price_of(ty),
				"ok": why == "", "why": why})
	return out


## Level of the building needed for a unit type (chain, level).
static func needs(key: String) -> Array:
	var ty := UT.index_of(key)
	var line := UT.line_of(ty)
	var lvl: int = CData.ART_LEVEL.get(line, UT.tier_of(ty))
	return [int(CData.LINE_CHAIN[line]), lvl]


static func recruit_check(st: Dictionary, f: int, r: int, key: String) -> String:
	if r < 0 or r >= CData.region_count():
		return "bad order"
	var rs: Dictionary = st["regions"][r]
	if int(rs["owner"]) != f:
		return "not your region"
	if not CState.siege_at(st, r).is_empty():
		return "besieged"
	var ty := UT.index_of(key)
	if ty < 0:
		return "unknown unit"
	var ok := false
	var ro: Dictionary = CData.roster(f)
	if ro.has(UT.line_of(ty)):
		ok = (ro[UT.line_of(ty)] as Array).has(key)
	if not ok:
		return "not in your roster"
	var nd := needs(key)
	if CState.building(st, r, nd[0]) < int(nd[1]):
		return "needs %s %d" % [CData.CHAINS[nd[0]]["name"], nd[1]]
	if (rs["queue"] as Array).size() >= int(CData.RECRUITS_PER_TURN[int(rs["level"])]):
		return "recruitment full this turn"
	if not CState.battle_at(st, r).is_empty():
		return "battle pending here"
	if UT.price_of(ty) > int(st["factions"][f]["treasury"]):
		return "not enough money"
	return ""


static func _recruit(st: Dictionary, f: int, r: int, key: String) -> String:
	var why := recruit_check(st, f, r, key)
	if why != "":
		return why
	st["factions"][f]["treasury"] = int(st["factions"][f]["treasury"]) - UT.price_of(UT.index_of(key))
	(st["regions"][r]["queue"] as Array).append(key)
	return ""


static func _own_free_army(st: Dictionary, f: int, id: int) -> Dictionary:
	var a := CState.army(st, id)
	if a.is_empty() or int(a["f"]) != f or int(a["busy"]) != 0 or siege_role(st, a) != 0:
		return {}
	return a


static func _merge(st: Dictionary, f: int, id: int, into: int) -> String:
	var a := _own_free_army(st, f, id)
	var b := _own_free_army(st, f, into)
	if a.is_empty() or b.is_empty() or id == into:
		return "no such army"
	if int(a["r"]) != int(b["r"]):
		return "not in the same region"
	if CState.unit_count(a) + CState.unit_count(b) > CData.ARMY_MAX:
		return "more than %d units" % CData.ARMY_MAX
	(b["units"] as Array).append_array(a["units"])
	if CState.moves_on(st):
		# The merged army moves at the pace of its slower part.
		b["mp"] = mini(mini(CState.mp(a), CState.mp(b)), CState.max_mp(b))
		b["moved"] = maxi(int(a["moved"]), int(b["moved"]))
	st["armies"].remove_at(CState.army_index(st, id))
	return ""


static func _unit_list(a: Dictionary, idx) -> Array:
	if not (idx is Array):
		return []
	var out: Array = []
	for v in idx:
		var k := int(v)
		if k < 0 or k >= CState.unit_count(a) or out.has(k):
			return []
		out.append(k)
	out.sort()
	return out


static func _split(st: Dictionary, f: int, id: int, idx, new_id: int) -> String:
	var a := _own_free_army(st, f, id)
	if a.is_empty():
		return "no such army"
	var list := _unit_list(a, idx)
	if list.is_empty() or list.size() >= CState.unit_count(a):
		return "choose some but not all units"
	if new_id != new_army_id(st, f):
		return "bad new army id"
	var moved: Array = []
	for k in range(list.size() - 1, -1, -1):
		moved.push_front((a["units"] as Array)[list[k]])
		(a["units"] as Array).remove_at(list[k])
	st["factions"][f]["next_army"] = int(st["factions"][f]["next_army"]) + 1
	var na := {"id": new_id, "f": f, "r": int(a["r"]), "units": moved,
		"from": int(a["from"]), "moved": int(a["moved"]), "busy": 0}
	if CState.moves_on(st):
		na["mp"] = mini(CState.mp(a), CState.max_mp(na))
		na["stance"] = CState.stance(a)
		a["mp"] = mini(CState.mp(a), CState.max_mp(a))
	_insert_army(st, na)
	return ""


static func _disband(st: Dictionary, f: int, id: int, idx) -> String:
	var a := _own_free_army(st, f, id)
	if a.is_empty():
		return "no such army"
	var list := _unit_list(a, idx)
	if list.is_empty():
		return "no units chosen"
	for k in range(list.size() - 1, -1, -1):
		(a["units"] as Array).remove_at(list[k])
	if CState.unit_count(a) == 0:
		st["armies"].remove_at(CState.army_index(st, id))
	return ""


static func _insert_army(st: Dictionary, a: Dictionary) -> void:
	if CState.moves_on(st):
		CState.army_defaults(a)
	var arr: Array = st["armies"]
	var i := 0
	while i < arr.size() and int(arr[i]["id"]) < int(a["id"]):
		i += 1
	arr.insert(i, a)


## "" if army a (of faction f, -1 = its own) may move to region `to` this
## turn (version 5: march towards it, any region it can reach).
static func can_move(st: Dictionary, a: Dictionary, to: int, f: int = -1) -> String:
	if a.is_empty() or (f >= 0 and int(a["f"]) != f):
		return "no such army"
	if CState.moves_on(st):
		return _can_march(st, a, to)
	if int(a["busy"]) != 0:
		return "in a battle"
	if int(a["moved"]) != 0:
		return "already moved"
	if to < 0 or to >= CData.region_count() or CData.link(int(a["r"]), to) < 0:
		return "not adjacent"
	if siege_role(st, a) == 2:
		return "besieged"
	if not CState.battle_at(st, to).is_empty():
		return "battle pending there"
	var af := int(a["f"])
	var o := CState.owner(st, to)
	var sg := CState.siege_at(st, to)
	if not sg.is_empty():
		# Join our side's siege, or relieve our own (or an ally's) city.
		if (CState.friendly(st, af, int(sg["f"])) and CState.at_war(st, af, o)) or CState.friendly(st, af, o):
			return ""
		return "besieged by " + CData.faction_name(int(sg["f"]))
	if CState.friendly(st, af, o) or CState.at_war(st, af, o):
		return ""
	return "at peace with " + CData.faction_name(o)


## Regions army a can move to (sorted). Version 5: every region it can
## reach (this_turn: only those it reaches this turn).
static func move_targets(st: Dictionary, a: Dictionary, this_turn: bool = false) -> Array[int]:
	var out: Array[int] = []
	if CState.moves_on(st):
		if a.is_empty() or int(a["busy"]) != 0 or int(a["moved"]) != 0 or siege_role(st, a) == 2:
			return out
		var rc := reach(st, a)
		for r in CData.region_count():
			if r != int(a["r"]) and int(rc["t"][r]) < INF and (not this_turn or int(rc["t"][r]) == 0):
				out.append(r)
		return out
	for e in CData.adjacent(int(a["r"])):
		if can_move(st, a, int(e[0])) == "":
			out.append(int(e[0]))
	return out


## Execute a validated move: the army arrives; entering a hostile region
## starts a battle there (sieges on: with mode MODE_SIEGE it lays siege
## instead), and entering a region where a battle started this turn joins it
## (see join_battle). Sieges: entering a region our side besieges joins the
## siege (mode MODE_ASSAULT: and storms it now), entering one of our side's
## besieged regions relieves it (a field battle). Leaving a siege as its last
## besieger lifts it. Returns "" or why it was bounced.
static func execute_move(st: Dictionary, a: Dictionary, to: int, mode: int = CData.MODE_ASSAULT) -> String:
	var b := CState.battle_at(st, to) if to >= 0 and to < CData.region_count() else {}
	if not b.is_empty() and int(b.get("new", 0)) != 0 and int(b["turn"]) == int(st["turn"]):
		return join_battle(st, a, b)
	var why := can_move(st, a, to)
	if why != "":
		return why
	var f := int(a["f"])
	var o := CState.owner(st, to)
	var left := int(a["r"])
	_arrive(a, to)
	if not CState.sieges_on(st):
		if CState.at_war(st, f, o):
			start_battle(st, to, a)
		return ""
	_left_siege(st, left)
	var sg := CState.siege_at(st, to)
	if not sg.is_empty():
		if CState.friendly(st, f, int(sg["f"])) and CState.at_war(st, f, o):
			_set_from(sg, int(a["id"]), left)
			if mode == CData.MODE_ASSAULT:
				start_siege_battle(st, to, "assault")
		else:
			start_siege_battle(st, to, "relief", a)
		return ""
	if CState.at_war(st, f, o):
		if mode == CData.MODE_ASSAULT:
			start_battle(st, to, a)
		else:
			start_siege(st, to, a, left)
	return ""


static func _arrive(a: Dictionary, to: int) -> void:
	a["from"] = int(a["r"])
	a["r"] = to
	a["moved"] = 1


## Army a moves into the region of battle b, started this turn: it joins the
## attackers if it is on their side (and at war with the owner), the
## defenders if it is on the owner's side, while that side has room for its
## units (BATTLE_SIDE_MAX field units). Returns "" or why it was bounced.
static func join_battle(st: Dictionary, a: Dictionary, b: Dictionary, marching: bool = false) -> String:
	if a.is_empty():
		return "no such army"
	if int(a["busy"]) != 0:
		return "in a battle"
	if int(a["moved"]) != 0 and not marching:
		return "already moved"
	var to := int(b["r"])
	if CData.link(int(a["r"]), to) < 0:
		return "not adjacent"
	var af := int(a["f"])
	var side := -1
	if CState.friendly(st, af, int(b["att_f"])) and CState.at_war(st, af, int(b["def_f"])):
		side = 0
	elif CState.friendly(st, af, int(b["def_f"])):
		side = 1
	if side < 0:
		return "battle pending there"
	var count := CState.unit_count(a)
	for d in battle_armies(st, b)[side]:
		count += CState.unit_count(d)
	if count > CData.BATTLE_SIDE_MAX:
		return "battle side full"
	var left := int(a["r"])
	_arrive(a, to)
	a["busy"] = 1
	(b["att" if side == 0 else "def"] as Array).append(int(a["id"]))
	if CState.sieges_on(st):
		if b.has("from"):
			(b["from"] as Array).append([int(a["id"]), left])
		var sg := CState.siege_at(st, to)
		if side == 0 and not sg.is_empty():
			_set_from(sg, int(a["id"]), left)
		_left_siege(st, left)
	return ""


## A new battle in region r: army a attacks the owner (garrison and the
## owner's and its allies' armies there).
static func start_battle(st: Dictionary, r: int, a: Dictionary) -> Dictionary:
	var o := CState.owner(st, r)
	var defs: Array = []
	for d in st["armies"]:
		if int(d["r"]) == r and int(d["id"]) != int(a["id"]) and CState.friendly(st, int(d["f"]), o) and o >= 0:
			defs.append(int(d["id"]))
			d["busy"] = 1
	a["busy"] = 1
	var b := {"id": int(st["next_battle"]), "r": r, "turn": int(st["turn"]), "att": [int(a["id"])],
		"def": defs, "att_f": int(a["f"]), "def_f": o, "reinf": [], "settlement": 1, "new": 1}
	if CState.sieges_on(st):
		b["from"] = [[int(a["id"]), int(a["from"])]]
	st["next_battle"] = int(st["next_battle"]) + 1
	(st["battles"] as Array).append(b)
	return b


# ------------------------------------------------ free movement (v5) ---
# State version 5 (CState.moves_on): armies have movement points (CState
# max_mp by their slowest arm), pay CData.move_cost to enter a region (a
# sea lane needs full points and takes them all), and walk the cheapest
# path to a destination hop by hop. A phase's moves run in rounds: round k
# moves every army's k-th hop, armies by id within a round. An enemy army
# in the field stops an army entering its region: a field battle there
# (kind "field"). Entering hostile land does not attack by itself (raiding:
# the owner gets half the region's income); laying siege or assaulting is
# an order (or a move's mode, applied on arrival).

const INF := 1 << 30


## "" if faction f may enter region r (pass through or stop there), else
## why not: a battle pending from an earlier turn (one started this turn
## can be joined), a siege by a third party, a faction at peace.
static func can_enter(st: Dictionary, f: int, r: int) -> String:
	var b := CState.battle_at(st, r)
	if not b.is_empty() and int(b.get("new", 0)) == 0:
		return "battle pending there"
	var o := CState.owner(st, r)
	var sg := CState.siege_at(st, r)
	if not sg.is_empty():
		if (CState.friendly(st, f, int(sg["f"])) and CState.at_war(st, f, o)) or CState.friendly(st, f, o):
			return ""
		return "besieged by " + CData.faction_name(int(sg["f"]))
	if CState.friendly(st, f, o) or CState.at_war(st, f, o):
		return ""
	return "at peace with " + CData.faction_name(o)


## Cheapest paths of army a from where it stands (Dijkstra over
## CData.adjacent, regions it may enter): per region "t" the turn it gets
## there (0 this turn, INF never), "m" the points it has left then, "prev"
## the region before it on the path. Ordered by (turn, most points left),
## ties by region index. land_only: no sea lanes. ok_in: optional per-region
## 1 / 0 for can_enter of the army's faction (callers planning many armies).
static func reach(st: Dictionary, a: Dictionary, land_only: bool = false, ok_in: Array[int] = []) -> Dictionary:
	_tables()
	var n := CData.region_count()
	var f := int(a["f"])
	var full := CState.max_mp(a)
	var t: Array[int] = []
	var m: Array[int] = []
	var prev: Array[int] = []
	var done: Array[int] = []
	var ok: Array[int] = []
	t.resize(n)
	m.resize(n)
	prev.resize(n)
	done.resize(n)
	t.fill(INF)
	m.fill(-1)
	prev.fill(-1)
	done.fill(0)
	if ok_in.size() == n:
		ok = ok_in
	else:
		ok.resize(n)
		ok.fill(-1)  # -1 unknown, 0 no, 1 yes
	var s := int(a["r"])
	t[s] = 0
	m[s] = clampi(CState.mp(a), 0, full)
	var open: Array[int] = [s]
	while not open.is_empty():
		var bi := 0
		for i in range(1, open.size()):
			var r := open[i]
			var u0 := open[bi]
			if t[r] < t[u0] or (t[r] == t[u0] and (m[r] > m[u0] or (m[r] == m[u0] and r < u0))):
				bi = i
		var u := open[bi]
		open.remove_at(bi)
		if done[u] != 0:
			continue
		done[u] = 1
		var nb: Array[int] = _t_adj[u]
		var sea_l: Array[int] = _t_sea[u]
		for k in nb.size():
			var v := nb[k]
			var sea := sea_l[k] == 1
			if done[v] != 0 or (sea and land_only):
				continue
			if ok[v] < 0:
				ok[v] = 1 if can_enter(st, f, v) == "" else 0
			if ok[v] == 0:
				continue
			var nt := t[u]
			var nm := 0
			if sea:
				if m[u] != full:
					nt += 1
			else:
				var c := _t_cost[v]
				if m[u] >= c:
					nm = m[u] - c
				elif m[u] != full:
					nt += 1
					nm = maxi(full - c, 0)
			if nt < t[v] or (nt == t[v] and nm > m[v]):
				if t[v] >= INF:
					open.append(v)
				elif not open.has(v):
					open.append(v)
				t[v] = nt
				m[v] = nm
				prev[v] = u
	return {"t": t, "m": m, "prev": prev}


static var _t_adj: Array = []
static var _t_sea: Array = []
static var _t_cost: Array[int] = []


## Static tables for reach(): neighbours, link kinds and entry costs.
static func _tables() -> void:
	if not _t_cost.is_empty():
		return
	for r in CData.region_count():
		var nb: Array[int] = []
		var sk: Array[int] = []
		for e in CData.adjacent(r):
			nb.append(int(e[0]))
			sk.append(int(e[1]))
		_t_adj.append(nb)
		_t_sea.append(sk)
		_t_cost.append(CData.move_cost(r))


## The hops from the army's region to `to` on reach() result rc (empty if
## unreachable or there already).
static func path_of(rc: Dictionary, to: int) -> Array:
	var out: Array = []
	if to < 0 or int(rc["t"][to]) >= INF:
		return out
	var r := to
	while int(rc["prev"][r]) >= 0:
		out.push_front(r)
		r = int(rc["prev"][r])
	return out


static func _can_march(st: Dictionary, a: Dictionary, to: int, rc: Dictionary = {}) -> String:
	if int(a["busy"]) != 0:
		return "in a battle"
	if int(a["moved"]) != 0:
		return "already moved"
	if to < 0 or to >= CData.region_count():
		return "no route"
	if siege_role(st, a) == 2:
		return "besieged"
	if to == int(a["r"]):
		return "already there"
	var why := can_enter(st, int(a["f"]), to)
	if why != "":
		return why
	if int((rc if not rc.is_empty() else reach(st, a))["t"][to]) >= INF:
		return "no route"
	return ""


## Version 5: run one phase's moves in rounds. moves: [[army id, dest,
## faction, mode, persist], ...]. Each army's path is computed now (the
## state as the phase starts); round k moves every army's k-th hop, by army
## id. An army stops when out of points, when it enters a battle (joins one
## started this turn, is intercepted by an enemy field army, relieves a
## siege) or is refused; with persist it keeps dest and mode for next turn.
## Arriving at dest with mode siege / assault in hostile land lays siege /
## storms the settlement (a field battle first if enemy field armies are
## there: the intent is kept and acted on after a won battle).
static func execute_moves(st: Dictionary, moves: Array) -> void:
	var list := moves.duplicate()
	list.sort_custom(func(x, y): return int(x[0]) < int(y[0]))
	var plans: Array = []
	var seen := {}
	for mv in list:
		var id := int(mv[0])
		if seen.has(id):
			continue
		seen[id] = 1
		var a := CState.army(st, id)
		if a.is_empty() or int(a["f"]) != int(mv[2]):
			continue
		var dest := int(mv[1])
		var mode := int(mv[3])
		var persist := int(mv[4]) if (mv as Array).size() > 4 else 0
		var why := ""
		var rc := {}
		if dest == int(a["r"]):
			why = _can_act_here(st, a, mode)
		else:
			rc = reach(st, a)
			why = _can_march(st, a, dest, rc)
		if why != "":
			event(st, {"k": "move_failed", "f": int(a["f"]), "army": id, "to": dest, "why": why})
			a["dest"] = -1
			a["mode"] = CData.MODE_MARCH
			continue
		var path: Array = [] if dest == int(a["r"]) else path_of(rc, dest)
		plans.append({"id": id, "path": path, "k": 0, "dest": dest, "mode": mode, "persist": persist, "stop": 0})
	# Armies already where they want to act (a stored siege / assault).
	for p in plans:
		if (p["path"] as Array).is_empty():
			_act_here(st, CState.army(st, int(p["id"])), int(p["mode"]))
	var moving := true
	while moving:
		moving = false
		for p in plans:
			var path: Array = p["path"]
			if int(p["stop"]) != 0 or int(p["k"]) >= path.size():
				continue
			var a := CState.army(st, int(p["id"]))
			if a.is_empty() or int(a["busy"]) != 0:
				p["stop"] = 1
				continue
			var to := int(path[int(p["k"])])
			var full := CState.max_mp(a)
			var left := CState.mp(a)
			var cost := 0
			if CData.link(int(a["r"]), to) == 1:
				if left < full:
					p["stop"] = 1
					continue
				cost = left
			else:
				cost = CData.move_cost(to)
				if left < cost:
					if left < full:
						p["stop"] = 1
						continue
					cost = left
			var final := int(p["k"]) == path.size() - 1
			var res := _hop(st, a, to, cost, final, int(p["mode"]))
			if res == "" or res == "stop":
				p["k"] = int(p["k"]) + 1
				moving = true
			if res != "":
				p["stop"] = 1
			if res != "" and res != "stop":
				event(st, {"k": "move_failed", "f": int(a["f"]), "army": int(a["id"]), "to": to, "why": res})
	for p in plans:
		var a := CState.army(st, int(p["id"]))
		if a.is_empty():
			continue
		var dest := int(p["dest"])
		if int(a["r"]) == dest:
			if not _intent_pending(st, a):
				a["dest"] = -1
				a["mode"] = CData.MODE_MARCH
		elif int(p["persist"]) != 0:
			a["dest"] = dest
			a["mode"] = int(p["mode"])
		else:
			a["dest"] = -1
			a["mode"] = CData.MODE_MARCH


## Army a stands at its destination with a siege / assault that waits for a
## field battle there to be won (see _act_here).
static func _intent_pending(st: Dictionary, a: Dictionary) -> bool:
	if int(a["dest"]) != int(a["r"]) or int(a["mode"]) == CData.MODE_MARCH:
		return false
	var b := CState.battle_at(st, int(a["r"]))
	return not b.is_empty() and str(b.get("kind", "")) == "field" and (b["att"] as Array).has(int(a["id"]))


## One hop of a march into `to` for `cost` points. Returns "" (moved on),
## "stop" (it entered and its march ends: a battle) or why it was refused.
static func _hop(st: Dictionary, a: Dictionary, to: int, cost: int, final: bool, mode: int) -> String:
	var f := int(a["f"])
	var b := CState.battle_at(st, to)
	if not b.is_empty():
		if int(b.get("new", 0)) == 0:
			return "battle pending there"
		var jw := join_battle(st, a, b, true)
		if jw != "":
			return jw
		_spend(a, cost)
		return "stop"
	var why := can_enter(st, f, to)
	if why != "":
		return why
	var o := CState.owner(st, to)
	var left := int(a["r"])
	var sg := CState.siege_at(st, to)
	if not sg.is_empty():
		_arrive(a, to)
		_spend(a, cost)
		_left_siege(st, left)
		if CState.friendly(st, f, int(sg["f"])) and CState.at_war(st, f, o):
			_set_from(sg, int(a["id"]), left)
			if final and mode == CData.MODE_ASSAULT:
				start_siege_battle(st, to, "assault")
				return "stop"
			return ""
		start_siege_battle(st, to, "relief", a)
		return "stop"
	var foes := hostile_field(st, to, f)
	_arrive(a, to)
	_spend(a, cost)
	_left_siege(st, left)
	if not foes.is_empty():
		var fb := start_field_battle(st, to, [a], foes)
		if final and mode != CData.MODE_MARCH and CState.at_war(st, f, o):
			a["dest"] = to
			a["mode"] = mode
		event(st, {"k": "intercepted", "r": to, "f": f, "by": int(fb["def_f"]), "army": int(a["id"])})
		return "stop"
	if final and mode != CData.MODE_MARCH and CState.at_war(st, f, o):
		_act_here(st, a, mode)
	return ""


static func _spend(a: Dictionary, cost: int) -> void:
	a["mp"] = maxi(CState.mp(a) - cost, 0)
	a["stance"] = CData.STANCE_FIELD


## Enemy armies (at war with f) in the field in region r, not in a battle:
## those that stop an army entering. Only the first one's side (allies of
## it) is returned.
static func hostile_field(st: Dictionary, r: int, f: int) -> Array:
	var out: Array = []
	var lead := -1
	for d in st["armies"]:
		if int(d["r"]) != r or int(d["busy"]) != 0 or CState.stance(d) != CData.STANCE_FIELD:
			continue
		var df := int(d["f"])
		if not CState.at_war(st, f, df):
			continue
		if lead < 0:
			lead = df
		if CState.friendly(st, df, lead):
			out.append(d)
	return out


## A field battle in region r (kind "field", no settlement, no garrison):
## the armies `att` attack the armies `defs` (each side up to
## BATTLE_SIDE_MAX field units). def_f is the first defender's faction.
static func start_field_battle(st: Dictionary, r: int, att: Array, defs: Array) -> Dictionary:
	var sides := [[], []]
	var groups := [att, defs]
	for s in 2:
		var count := 0
		for a in groups[s]:
			if count > 0 and count + CState.unit_count(a) > CData.BATTLE_SIDE_MAX:
				continue
			count += CState.unit_count(a)
			sides[s].append(int(a["id"]))
			a["busy"] = 1
	var from: Array = []
	for a in att:
		if sides[0].has(int(a["id"])) and int(a["from"]) >= 0:
			from.append([int(a["id"]), int(a["from"])])
	for a in defs:
		if sides[1].has(int(a["id"])) and int(a["from"]) >= 0 and int(a["from"]) != r:
			from.append([int(a["id"]), int(a["from"])])
	var b := {"id": int(st["next_battle"]), "r": r, "turn": int(st["turn"]), "att": sides[0], "def": sides[1],
		"att_f": int(att[0]["f"]), "def_f": int(defs[0]["f"]), "reinf": [], "settlement": 0, "new": 1,
		"kind": "field", "from": from, "edge": []}
	st["next_battle"] = int(st["next_battle"]) + 1
	(st["battles"] as Array).append(b)
	return b


## "" if army a, standing where it is, may lay siege (mode 0) or storm the
## settlement (mode 1) there now.
static func _can_act_here(st: Dictionary, a: Dictionary, mode: int) -> String:
	if mode == CData.MODE_MARCH:
		return "already there"
	if int(a["busy"]) != 0:
		return "in a battle"
	var r := int(a["r"])
	if not CState.at_war(st, int(a["f"]), CState.owner(st, r)):
		return "not hostile land"
	if not CState.battle_at(st, r).is_empty():
		return "battle pending there"
	var sg := CState.siege_at(st, r)
	if not sg.is_empty() and mode == CData.MODE_SIEGE:
		return "already besieged"
	return ""


## Army a (in hostile region r) lays siege (MODE_SIEGE) or storms the
## settlement (MODE_ASSAULT) with the armies of its side there. Enemy armies
## in the field there are fought first (a field battle; the intent is kept
## on the army: dest r, mode, acted on when the battle is won).
static func _act_here(st: Dictionary, a: Dictionary, mode: int) -> void:
	if a.is_empty() or _can_act_here(st, a, mode) != "":
		return
	var r := int(a["r"])
	var f := int(a["f"])
	var sg := CState.siege_at(st, r)
	if not sg.is_empty():
		start_siege_battle(st, r, "assault")
		return
	var foes := hostile_field(st, r, f)
	if not foes.is_empty():
		start_field_battle(st, r, _side_here(st, r, a), foes)
		a["dest"] = r
		a["mode"] = mode
		return
	if mode == CData.MODE_SIEGE:
		start_siege(st, r, a, int(a["from"]))
	else:
		var b := start_battle(st, r, a)
		var count := CState.unit_count(a)
		for d in _side_here(st, r, a):
			if int(d["id"]) == int(a["id"]) or count + CState.unit_count(d) > CData.BATTLE_SIDE_MAX:
				continue
			count += CState.unit_count(d)
			(b["att"] as Array).append(int(d["id"]))
			d["busy"] = 1
			if int(d["from"]) >= 0:
				(b["from"] as Array).append([int(d["id"]), int(d["from"])])


## Army a and the armies of its side in region r not in a battle (by id).
static func _side_here(st: Dictionary, r: int, a: Dictionary) -> Array:
	var out: Array = [a]
	var o := CState.owner(st, r)
	for d in st["armies"]:
		if int(d["r"]) == r and int(d["id"]) != int(a["id"]) and int(d["busy"]) == 0 \
				and CState.friendly(st, int(d["f"]), int(a["f"])) and CState.at_war(st, int(d["f"]), o):
			out.append(d)
	return out


## The attackers won a field battle in region r: an army that meant to lay
## siege there does so now; one that meant to storm it keeps the order for
## next turn (its dest and mode).
static func _after_field_win(st: Dictionary, r: int, attackers: Array) -> void:
	for a in attackers:
		if CState.army_index(st, int(a["id"])) < 0 or int(a["r"]) != r or int(a["dest"]) != r:
			continue
		if int(a["mode"]) == CData.MODE_SIEGE:
			a["dest"] = -1
			a["mode"] = CData.MODE_MARCH
			if _can_act_here(st, a, CData.MODE_SIEGE) == "" and hostile_field(st, r, int(a["f"])).is_empty():
				start_siege(st, r, a, int(a["from"]))


## "" if faction f may order a siege of region r from inside: one of its
## armies stands there, at war with the owner, no siege or battle yet.
static func can_siege(st: Dictionary, f: int, r: int) -> String:
	if not CState.moves_on(st):
		return "no free movement in this campaign"
	if r < 0 or r >= CData.region_count():
		return "bad order"
	if not CState.siege_at(st, r).is_empty():
		return "already besieged"
	if not CState.at_war(st, f, CState.owner(st, r)):
		return "not hostile land"
	if not CState.battle_at(st, r).is_empty():
		return "battle pending there"
	if _mine_here(st, f, r).is_empty():
		return "none of your armies are there"
	return ""


## Faction f's armies in region r that are free to act (not in a battle).
static func _mine_here(st: Dictionary, f: int, r: int) -> Array:
	var out: Array = []
	for a in st["armies"]:
		if int(a["r"]) == r and int(a["f"]) == f and int(a["busy"]) == 0:
			out.append(a)
	return out


static func order_siege(st: Dictionary, f: int, r: int) -> String:
	if r >= 0 and r < CData.region_count() and CState.at_war(st, f, CState.owner(st, r)):
		var sg := CState.siege_at(st, r)
		if not sg.is_empty() and CState.friendly(st, f, int(sg["f"])) and int(sg["turn"]) == int(st["turn"]):
			return ""  # the ally laid it this turn
	var why := can_siege(st, f, r)
	if why != "":
		return why
	_act_here(st, _mine_here(st, f, r)[0], CData.MODE_SIEGE)
	return ""


## Stance order (version 5): 1 inside the walls of a settlement of our side,
## 0 in the field. Taking the field where enemy armies stand rides out to
## fight them (a field battle). No points spent.
static func _set_stance(st: Dictionary, f: int, id: int, s: int) -> String:
	if not CState.moves_on(st):
		return "no free movement in this campaign"
	var a := CState.army(st, id)
	if a.is_empty() or int(a["f"]) != f:
		return "no such army"
	if int(a["busy"]) != 0:
		return "in a battle"
	var r := int(a["r"])
	if s != CData.STANCE_FIELD and s != CData.STANCE_GARRISON:
		return "bad order"
	if CState.stance(a) == s:
		return ""
	if not CState.siege_at(st, r).is_empty():
		return "besieged"
	if s == CData.STANCE_GARRISON:
		if not CState.friendly(st, f, CState.owner(st, r)):
			return "not your settlement"
		a["stance"] = s
		return ""
	a["stance"] = s
	var foes: Array = []
	for d in st["armies"]:
		if int(d["r"]) == r and int(d["busy"]) == 0 and CState.at_war(st, f, int(d["f"])):
			if foes.is_empty() or CState.friendly(st, int(d["f"]), int(foes[0]["f"])):
				foes.append(d)
	if not foes.is_empty():
		start_field_battle(st, r, [a], foes)
	return ""


static func _cancel_move(st: Dictionary, f: int, id: int) -> String:
	if not CState.moves_on(st):
		return "no free movement in this campaign"
	var a := CState.army(st, id)
	if a.is_empty() or int(a["f"]) != f:
		return "no such army"
	a["dest"] = -1
	a["mode"] = CData.MODE_MARCH
	return ""


## Version 5: armies left in the land of a faction they are at peace with
## (peace made while they stood there) go home; armies inside the walls of
## a settlement no longer their side's take the field.
static func _check_trespass(st: Dictionary) -> void:
	for a in (st["armies"] as Array).duplicate():
		if int(a["busy"]) != 0:
			continue
		var r := int(a["r"])
		var o := CState.owner(st, r)
		var af := int(a["f"])
		if not CState.friendly(st, af, o) and CState.stance(a) != CData.STANCE_FIELD:
			a["stance"] = CData.STANCE_FIELD
		if not CState.friendly(st, af, o) and not CState.at_war(st, af, o) and CState.siege_at(st, r).is_empty():
			_retreat(st, a, -1, true)


# --------------------------------------------------------------- sieges ---

## 0: army a is not in a siege; 1: it besieges the region it is in; 2: it is
## inside a besieged settlement of its own side.
static func siege_role(st: Dictionary, a: Dictionary) -> int:
	if a.is_empty() or not CState.sieges_on(st):
		return 0
	var r := int(a["r"])
	var sg := CState.siege_at(st, r)
	if sg.is_empty():
		return 0
	var af := int(a["f"])
	var o := CState.owner(st, r)
	if CState.friendly(st, af, o):
		return 2
	if CState.friendly(st, af, int(sg["f"])) and CState.at_war(st, af, o):
		return 1
	return 0


## Armies besieging region r (by id): there, on the siege's side, at war
## with the owner.
static func besiegers(st: Dictionary, r: int) -> Array:
	var out: Array = []
	var sg := CState.siege_at(st, r)
	if sg.is_empty():
		return out
	var o := CState.owner(st, r)
	for a in st["armies"]:
		if int(a["r"]) == r and CState.friendly(st, int(a["f"]), int(sg["f"])) and CState.at_war(st, int(a["f"]), o):
			out.append(a)
	return out


## Armies of the owner's side inside besieged region r (by id).
static func besieged_armies(st: Dictionary, r: int) -> Array:
	var out: Array = []
	if CState.siege_at(st, r).is_empty():
		return out
	var o := CState.owner(st, r)
	for a in st["armies"]:
		if int(a["r"]) == r and CState.friendly(st, int(a["f"]), o):
			out.append(a)
	return out


## Army a (just arrived from region `left`) lays siege to region r.
static func start_siege(st: Dictionary, r: int, a: Dictionary, left: int) -> Dictionary:
	var sg := {"r": r, "f": int(a["f"]), "turn": int(st["turn"]), "supply": CState.siege_supply(st, r),
		"held": 0, "from": [[int(a["id"]), left]]}
	var arr: Array = st["sieges"]
	var i := 0
	while i < arr.size() and int(arr[i]["r"]) < r:
		i += 1
	arr.insert(i, sg)
	event(st, {"k": "siege", "r": r, "f": int(a["f"]), "o": CState.owner(st, r)})
	return sg


static func _set_from(sg: Dictionary, id: int, left: int) -> void:
	var list: Array = sg["from"]
	for p in list:
		if int(p[0]) == id:
			p[1] = left
			return
	list.append([id, left])


## An army left region r: if it was the last besieger, the siege is lifted.
static func _left_siege(st: Dictionary, r: int) -> void:
	if r < 0 or CState.siege_at(st, r).is_empty():
		return
	if besiegers(st, r).is_empty():
		lift_siege(st, r, "left")


static func lift_siege(st: Dictionary, r: int, why: String) -> void:
	var sg := CState.siege_at(st, r)
	if sg.is_empty():
		return
	st["sieges"].erase(sg)
	if why != "":
		event(st, {"k": "siege_lifted", "r": r, "f": int(sg["f"]), "o": CState.owner(st, r), "why": why})


## A battle of the siege of region r: "assault" (settlement battle: the
## besiegers storm it), "sally" (the garrison and the armies inside ride
## out) or "relief" (army `reliever` arrived to lift it; the garrison and
## the armies inside join it). The besiegers attack in the record ("att",
## att_f the siege's faction), the owner's side defends ("def", with the
## garrison); besiegers beyond BATTLE_SIDE_MAX field units stay out.
static func start_siege_battle(st: Dictionary, r: int, kind: String, reliever: Dictionary = {}) -> Dictionary:
	var sg := CState.siege_at(st, r)
	if sg.is_empty():
		return {}
	var att: Array = []
	var count := 0
	var lead := -1
	for a in besiegers(st, r):
		if int(a["busy"]) != 0 or count + CState.unit_count(a) > CData.BATTLE_SIDE_MAX:
			continue
		count += CState.unit_count(a)
		att.append(int(a["id"]))
		if lead < 0 or int(a["f"]) == int(sg["f"]):
			lead = int(a["f"])
	if att.is_empty():
		return {}
	var defs: Array = []
	for a in besieged_armies(st, r):
		if int(a["busy"]) == 0:
			defs.append(int(a["id"]))
	for a in st["armies"]:
		if att.has(int(a["id"])) or defs.has(int(a["id"])):
			a["busy"] = 1
	var from: Array = []
	for p in sg["from"]:
		if att.has(int(p[0])):
			from.append([int(p[0]), int(p[1])])
	if not reliever.is_empty():
		from.append([int(reliever["id"]), int(reliever["from"])])
	var b := {"id": int(st["next_battle"]), "r": r, "turn": int(st["turn"]), "att": att, "def": defs,
		"att_f": lead, "def_f": CState.owner(st, r), "reinf": [], "settlement": 1 if kind == "assault" else 0,
		"new": 1, "kind": kind, "from": from}
	st["next_battle"] = int(st["next_battle"]) + 1
	(st["battles"] as Array).append(b)
	sg["held"] = 0
	return b


## "" if faction f may order the assault of besieged region r (one of its
## armies besieges it, no battle there yet).
static func can_assault(st: Dictionary, f: int, r: int) -> String:
	if not CState.sieges_on(st):
		return "no sieges in this campaign"
	if r < 0 or r >= CData.region_count():
		return "bad order"
	if CState.siege_at(st, r).is_empty() and CState.moves_on(st):
		# Version 5: storm it from where our armies stand (raiding).
		if not CState.at_war(st, f, CState.owner(st, r)):
			return "not hostile land"
		if not CState.battle_at(st, r).is_empty():
			return "battle pending there"
		if _mine_here(st, f, r).is_empty():
			return "none of your armies are there"
		return ""
	if CState.siege_at(st, r).is_empty():
		return "no siege there"
	var mine := false
	for a in besiegers(st, r):
		if int(a["f"]) == f:
			mine = true
	if not mine:
		return "none of your armies besiege it"
	if not CState.battle_at(st, r).is_empty():
		return "battle pending there"
	return ""


## "" if faction f may order a sally from besieged region r (its own city,
## or an ally's with one of f's armies inside; somebody left to fight).
static func can_sally(st: Dictionary, f: int, r: int) -> String:
	if not CState.sieges_on(st):
		return "no sieges in this campaign"
	if r < 0 or r >= CData.region_count():
		return "bad order"
	if CState.siege_at(st, r).is_empty():
		return "no siege there"
	var o := CState.owner(st, r)
	if not CState.friendly(st, f, o):
		return "not your city"
	var inside := besieged_armies(st, r)
	var mine := f == o
	for a in inside:
		if int(a["f"]) == f:
			mine = true
	if not mine:
		return "none of your armies are inside"
	if not CState.battle_at(st, r).is_empty():
		return "battle pending there"
	if inside.is_empty() and int(st["regions"][r]["gar"]) <= 0:
		return "nobody left to sally"
	return ""


## Execute an assault order (both allies ordering it make one battle).
static func order_assault(st: Dictionary, f: int, r: int) -> String:
	var b := CState.battle_at(st, r) if r >= 0 and r < CData.region_count() else {}
	if not b.is_empty() and str(b.get("kind", "")) in ["assault", "", "field"] and int(b["turn"]) == int(st["turn"]) \
			and int(b.get("new", 0)) != 0 and CState.friendly(st, f, int(b["att_f"])):
		return ""  # an ally's assault this turn already (both armies are in it)
	var why := can_assault(st, f, r)
	if why != "":
		return why
	if CState.siege_at(st, r).is_empty():
		_act_here(st, _mine_here(st, f, r)[0], CData.MODE_ASSAULT)
		return ""
	start_siege_battle(st, r, "assault")
	return ""


static func order_sally(st: Dictionary, f: int, r: int) -> String:
	var b := CState.battle_at(st, r) if r >= 0 and r < CData.region_count() else {}
	if not b.is_empty() and str(b.get("kind", "")) == "sally" and int(b["turn"]) == int(st["turn"]) \
			and CState.friendly(st, f, int(b["def_f"])):
		return ""
	var why := can_sally(st, f, r)
	if why != "":
		return why
	start_siege_battle(st, r, "sally")
	return ""


## Keep the sieges consistent after diplomacy, battles and eliminations:
## armies left at peace in a besieged region go home; a siege without
## besiegers is lifted, one whose settlement changed hands ends; the lead
## faction passes to a remaining besieger; origins of gone armies drop.
static func check_sieges(st: Dictionary) -> void:
	if not CState.sieges_on(st):
		return
	if CState.moves_on(st):
		_check_trespass(st)
	for sg in (st["sieges"] as Array).duplicate():
		var r := int(sg["r"])
		var o := CState.owner(st, r)
		for a in CState.armies_in(st, r):
			if int(a["busy"]) == 0 and not CState.friendly(st, int(a["f"]), o) and not CState.at_war(st, int(a["f"]), o):
				_retreat(st, a, _siege_origin(sg, int(a["id"])), true)
		if CState.friendly(st, int(sg["f"]), o):
			st["sieges"].erase(sg)
			continue
		var bs := besiegers(st, r)
		if bs.is_empty():
			lift_siege(st, r, "gone")
			continue
		var lead_here := false
		var ids: Array = []
		for a in bs:
			ids.append(int(a["id"]))
			if int(a["f"]) == int(sg["f"]):
				lead_here = true
		if not lead_here:
			sg["f"] = int(bs[0]["f"])
		var keep: Array = []
		for p in sg["from"]:
			if ids.has(int(p[0])):
				keep.append(p)
		sg["from"] = keep


static func _siege_origin(sg: Dictionary, id: int) -> int:
	for p in sg.get("from", []):
		if int(p[0]) == id:
			return int(p[1])
	return -1


## Where army a came from into battle b's region (the battle's record, else
## the army's "from" this turn).
static func _origin(st: Dictionary, b: Dictionary, a: Dictionary) -> int:
	for p in b.get("from", []):
		if int(p[0]) == int(a["id"]):
			return int(p[1])
	var sg := CState.siege_at(st, int(b["r"]))
	var o := _siege_origin(sg, int(a["id"])) if not sg.is_empty() else -1
	return o if o >= 0 else int(a["from"])


static func _arrived(b: Dictionary, a: Dictionary) -> bool:
	for p in b.get("from", []):
		if int(p[0]) == int(a["id"]):
			return true
	return false


## End of turn for every siege without a battle pending: supplies run down,
## then the garrison starves (and the owner's armies inside lose men); a
## settlement with no garrison left and no army of the owner inside
## surrenders to the besiegers.
static func _siege_turn(st: Dictionary) -> void:
	if not CState.sieges_on(st):
		return
	for sg in (st["sieges"] as Array).duplicate():
		var r := int(sg["r"])
		if not CState.battle_at(st, r).is_empty():
			continue
		var rs: Dictionary = st["regions"][r]
		sg["held"] = int(sg["held"]) + 1
		if int(sg["supply"]) > 0:
			sg["supply"] = int(sg["supply"]) - 1
		else:
			rs["gar"] = maxi(int(rs["gar"]) - CData.SIEGE_STARVE_PCT, 0)
			for a in besieged_armies(st, r):
				for unit in a["units"]:
					unit["n"] = maxi(int(unit["n"]) - maxi(int(unit["n"]) * CData.SIEGE_STARVE_ARMY_PCT / 100, 1), 0)
				var keep: Array = []
				for unit in a["units"]:
					if int(unit["n"]) > 0:
						keep.append(unit)
				a["units"] = keep
			_drop_empty_armies(st)
			event(st, {"k": "starving", "r": r, "f": CState.owner(st, r), "by": int(sg["f"]), "gar": int(rs["gar"])})
		if int(rs["gar"]) <= 0 and besieged_armies(st, r).is_empty():
			var bs := besiegers(st, r)
			if bs.is_empty():
				continue
			var w := int(bs[0]["f"])
			for a in bs:
				if int(a["f"]) == int(sg["f"]):
					w = int(sg["f"])
			_capture(st, r, w, "surrendered")


## Armies of each side in battle b: [attackers, defenders] (Arrays of army
## dictionaries, field armies and reinforcements, by id).
static func battle_armies(st: Dictionary, b: Dictionary) -> Array:
	var sides := [[], []]
	for a in st["armies"]:
		var id := int(a["id"])
		if (b["att"] as Array).has(id):
			sides[0].append(a)
		elif (b["def"] as Array).has(id):
			sides[1].append(a)
		elif (b["reinf"] as Array).has(id):
			var side := 0 if CState.friendly(st, int(a["f"]), int(b["att_f"])) else 1
			sides[side].append(a)
	return sides


static func in_battle(st: Dictionary, id: int) -> bool:
	for b in st["battles"]:
		if (b["att"] as Array).has(id) or (b["def"] as Array).has(id) or (b["reinf"] as Array).has(id):
			return true
	return false


## Factions on each side of battle b: [attackers, defenders].
static func battle_factions(st: Dictionary, b: Dictionary) -> Array:
	var out := [[], []]
	var arm := battle_armies(st, b)
	for s in 2:
		for a in arm[s]:
			if not out[s].has(int(a["f"])):
				out[s].append(int(a["f"]))
	if not out[1].has(int(b["def_f"])):
		out[1].append(int(b["def_f"]))
	out[0].sort()
	out[1].sort()
	return out


static func battle_humans(st: Dictionary, b: Dictionary) -> Array:
	var out: Array = []
	for side in battle_factions(st, b):
		for f in side:
			if CState.is_human(st, f) and not out.has(f):
				out.append(f)
	out.sort()
	return out


## Neighbouring armies join the battle (land routes only; armies that did
## not move and are not committed elsewhere; until a side has
## BATTLE_SIDE_MAX field units).
static func add_reinforcements(st: Dictionary, b: Dictionary) -> void:
	var arm := battle_armies(st, b)
	var counts := [0, 0]
	for s in 2:
		for a in arm[s]:
			counts[s] += CState.unit_count(a)
	var leads := [int(b["att_f"]), int(b["def_f"])]
	if CState.moves_on(st):
		_support_by_range(st, b, counts, leads)
		return
	for a in st["armies"]:
		if int(a["busy"]) != 0 or int(a["moved"]) != 0 or siege_role(st, a) != 0:
			continue
		if CData.link(int(a["r"]), int(b["r"])) != 0:
			continue
		for s in 2:
			if leads[s] < 0 or not CState.friendly(st, int(a["f"]), leads[s]):
				continue
			if counts[s] + CState.unit_count(a) > CData.BATTLE_SIDE_MAX:
				continue
			counts[s] += CState.unit_count(a)
			(b["reinf"] as Array).append(int(a["id"]))
			a["busy"] = 1


## Version 5: armies that did not move this turn, stand in the field and
## can reach the battle's region this turn over land (cheapest path within
## their full movement points; sea lanes never count) join it, until a side
## has BATTLE_SIDE_MAX field units. Each records in b["edge"] the compass
## sector it comes from (CData.sector of its region seen from the battle;
## -1 already there): the battle map deploys it on that edge.
static func _support_by_range(st: Dictionary, b: Dictionary, counts: Array, leads: Array) -> void:
	var br := int(b["r"])
	if not b.has("edge"):
		b["edge"] = []
	for a in st["armies"]:
		if int(a["busy"]) != 0 or int(a["moved"]) != 0 or siege_role(st, a) != 0 \
				or CState.stance(a) != CData.STANCE_FIELD:
			continue
		var af := int(a["f"])
		var side := -1
		for s in 2:
			if side < 0 and leads[s] >= 0 and CState.friendly(st, af, leads[s]):
				side = s
		if side < 0 or counts[side] + CState.unit_count(a) > CData.BATTLE_SIDE_MAX:
			continue
		var ar := int(a["r"])
		if ar != br and land_hops(ar, br) > CState.max_mp(a) / CData.COST_OPEN:
			continue
		if ar != br and int(reach(st, a, true)["t"][br]) != 0:
			continue
		counts[side] += CState.unit_count(a)
		(b["reinf"] as Array).append(int(a["id"]))
		(b["edge"] as Array).append([int(a["id"]), CData.sector(br, ar)])
		a["busy"] = 1


static var _land_hops: Array = []


## Land routes between regions a and b (breadth first; 99 if none), cached.
static func land_hops(a: int, b: int) -> int:
	var n := CData.region_count()
	if _land_hops.is_empty():
		var tab: Array = []
		for s in n:
			var d: Array[int] = []
			d.resize(n)
			d.fill(99)
			d[s] = 0
			var q: Array[int] = [s]
			var qi := 0
			while qi < q.size():
				var r := q[qi]
				qi += 1
				for e in CData.adjacent(r):
					if int(e[1]) == 0 and d[int(e[0])] > d[r] + 1:
						d[int(e[0])] = d[r] + 1
						q.append(int(e[0]))
			tab.append(d)
		_land_hops = tab
	return int(_land_hops[a][b])


# ------------------------------------------------------------- garrison ---

## Garrison of region r as units [{t, n, full}] at its current strength:
## GARRISON_UNITS[level] + walls units of GARRISON_SIZE_PCT size, tier from
## the settlement level and walls, types from the owner's roster.
static func garrison(st: Dictionary, r: int) -> Array:
	var rs: Dictionary = st["regions"][r]
	var o := int(rs["owner"])
	var lvl := int(rs["level"])
	var w := CState.walls(st, r)
	var count := int(CData.GARRISON_UNITS[lvl]) + w
	var tier := clampi(1 + (1 if lvl == CData.CITY else 0) + (1 if w >= 2 else 0), 1, 3)
	if o < 0:
		# Independent peoples raise every man to defend their home.
		count += CData.INDEPENDENT_EXTRA_UNITS
	var pattern := ["spear", "missile", "melee", "spear", "missile", "melee", "spear"]
	var out: Array = []
	for k in count:
		var key := _garrison_type(o, pattern[k % pattern.size()], tier)
		var ty := UT.index_of(key)
		var full := UT.size_of(ty) * (CData.GARRISON_SIZE_PCT if o >= 0 else CData.INDEPENDENT_SIZE_PCT) / 100
		out.append({"t": key, "n": maxi(full * int(rs["gar"]) / 100, 1 if int(rs["gar"]) > 0 else 0), "full": full})
	return out


static func _garrison_type(f: int, kind: String, tier: int) -> String:
	var lines: Array = {"spear": ["spear", "pike", "heavy", "light"],
		"missile": ["archer", "javelin", "light"], "melee": ["heavy", "light", "spear", "pike"]}[kind]
	for t in range(tier, 0, -1):
		for line in lines:
			var key := CState.roster_type(f, line, t)
			if key != "":
				return key
	return "spear"


# -------------------------------------------------------- battle outcome ---

## Apply a battle's outcome (see the header) and remove the battle.
static func apply_outcome(st: Dictionary, bid: int, outcome: Dictionary) -> void:
	var b := CState.battle(st, bid)
	if b.is_empty():
		return
	var r := int(b["r"])
	var kind := str(b.get("kind", ""))
	# A sally or relief (field battle of a siege): the owner's side is "def".
	var field := kind == "sally" or kind == "relief"
	# Version 5: an interception or a fight before a siege ("field"): two
	# groups of armies in the open, no garrison; the loser falls back.
	var open_field := kind == "field"
	var winner := int(outcome.get("winner", 1))
	if winner != 0:
		winner = 1
	if field and int(outcome.get("draw", 0)) != 0:
		winner = 0  # a drawn sortie leaves the besiegers where they are
	var facs := battle_factions(st, b)
	var lost := [0, 0]
	var before := [0, 0]
	var arm := battle_armies(st, b)
	for s in 2:
		for a in arm[s]:
			before[s] += CState.men(a)
	# Losses per unit.
	for u in outcome.get("units", []):
		var aid := int(u["army"])
		if aid < 0:
			continue
		var a := CState.army(st, aid)
		if a.is_empty():
			continue
		var k := int(u["unit"])
		if k < 0 or k >= CState.unit_count(a):
			continue
		var unit: Dictionary = a["units"][k]
		var back := int(u["remaining"]) + int(u["withdrawn"]) + int(u["routed"]) * CData.ROUT_RETURN / 100
		unit["n"] = clampi(back, 0, int(unit["n"]))
	for a in st["armies"]:
		var keep: Array = []
		for unit in a["units"]:
			if int(unit["n"]) > 0:
				keep.append(unit)
		a["units"] = keep
	_drop_empty_armies(st)
	arm = battle_armies(st, b)
	for s in 2:
		var now := 0
		for a in arm[s]:
			now += CState.men(a)
		lost[s] = before[s] - now
	var rs: Dictionary = st["regions"][r]
	if not open_field:
		rs["gar"] = clampi(int(outcome.get("garrison_pct", rs["gar"])), 0, 100)
	# Reinforcements stay where they are; armies in the region retreat if
	# their side lost.
	var loser := 1 - winner
	for a in arm[loser]:
		a["busy"] = 0
		if (b["reinf"] as Array).has(int(a["id"])):
			continue
		if open_field:
			# Back along the way it came, else the nearest friendly region.
			_retreat(st, a, _origin(st, b, a), true)
			continue
		if field:
			if loser == 0:
				# The siege is broken: the besiegers fall back to where they
				# came from, else to the nearest friendly region.
				_retreat(st, a, _origin(st, b, a), true)
			elif _arrived(b, a):
				_retreat(st, a, _origin(st, b, a))  # the relief is beaten off
			continue  # the armies inside stay behind their walls
		_retreat(st, a, _origin(st, b, a) if loser == 0 else -1)
	for a in arm[winner]:
		a["busy"] = 0
	var new_owner := -1
	if open_field:
		st["battles"].erase(b)
		if winner == 0:
			_after_field_win(st, r, arm[0])
	if winner == 0 and not field and not open_field:
		# The attackers take the settlement: the lead attacker if it still
		# has an army in the region, else the first attacking army there.
		var lead := int(b["att_f"])
		var present := -1
		for a in arm[0]:
			if int(a["r"]) == r:
				if int(a["f"]) == lead:
					present = lead
					break
				if present < 0:
					present = int(a["f"])
		if present >= 0:
			new_owner = present
			_capture(st, r, present)
		else:
			rs["gar"] = maxi(int(rs["gar"]), 10)
	st["battles"].erase(b)
	var stats: Dictionary = st["stats"]
	var mode := str(outcome.get("mode", "formula"))
	stats["battles"] = int(stats.get("battles", 0)) + 1
	stats["battles_" + mode] = int(stats.get("battles_" + mode, 0)) + 1
	var ev := {"k": "battle", "r": r, "att": facs[0], "def": facs[1], "winner": winner, "mode": mode,
		"att_lost": lost[0], "def_lost": lost[1], "att_men": before[0], "def_men": before[1],
		"captured": 1 if new_owner >= 0 else 0, "battle": bid}
	if kind != "":
		ev["kind"] = kind
	event(st, ev)
	check_eliminations(st)
	check_sieges(st)
	check_victory(st)
	if (st["battles"] as Array).is_empty() and str(st["phase"]) == "battles":
		st["phase"] = "plan"


static func _capture(st: Dictionary, r: int, f: int, how: String = "") -> void:
	var rs: Dictionary = st["regions"][r]
	var old := int(rs["owner"])
	rs["owner"] = f
	rs["gar"] = CData.CAPTURED_GARRISON
	rs["build"] = []
	rs["queue"] = []
	var e := {"k": "captured", "r": r, "f": f, "from": old}
	if how != "":
		e["how"] = how
	event(st, e)
	var sg := CState.siege_at(st, r)
	if not sg.is_empty():
		st["sieges"].erase(sg)
	if CState.sieges_on(st):
		# Armies of the old side left in the city (raised there while its
		# battle was pending) march out (version 4; older states keep them).
		for a in CState.armies_in(st, r):
			if int(a["busy"]) == 0 and not CState.friendly(st, int(a["f"]), f):
				_retreat(st, a, -1)


## Move a beaten army to a neighbouring friendly region (its origin if
## given and still friendly; else land before sea, lowest index), or
## destroy it. far: with no friendly neighbour, the nearest friendly region
## (breadth first over land routes and sea lanes, lowest index first).
static func _retreat(st: Dictionary, a: Dictionary, prefer: int, far: bool = false) -> void:
	var f := int(a["f"])
	var opts: Array[int] = []
	if prefer >= 0 and _retreat_ok(st, f, prefer, int(a["r"])):
		opts.append(prefer)
	for kind in 2:
		for e in CData.adjacent(int(a["r"])):
			if int(e[1]) == kind and _retreat_ok(st, f, int(e[0]), int(a["r"])):
				opts.append(int(e[0]))
	if opts.is_empty() and far:
		var t := _nearest_friendly(st, f, int(a["r"]))
		if t >= 0:
			opts.append(t)
	var from := int(a["r"])
	if opts.is_empty():
		event(st, {"k": "destroyed", "f": f, "r": from, "army": int(a["id"]), "men": CState.men(a)})
		st["armies"].erase(a)
		return
	a["r"] = opts[0]
	a["moved"] = 1
	if CState.moves_on(st):
		a["mp"] = 0
		a["dest"] = -1
		a["mode"] = CData.MODE_MARCH
		a["stance"] = CData.STANCE_FIELD
	event(st, {"k": "retreat", "f": f, "r": from, "to": opts[0], "army": int(a["id"])})


static func _retreat_ok(st: Dictionary, f: int, r: int, from: int) -> bool:
	if r == from or not CState.friendly(st, f, CState.owner(st, r)):
		return false
	return CState.battle_at(st, r).is_empty() and CState.siege_at(st, r).is_empty()


static func _nearest_friendly(st: Dictionary, f: int, from: int) -> int:
	var n := CData.region_count()
	var dist: Array[int] = []
	dist.resize(n)
	dist.fill(-1)
	dist[from] = 0
	var queue: Array[int] = [from]
	var qi := 0
	var best := -1
	var best_d := 1 << 20
	while qi < queue.size():
		var r := queue[qi]
		qi += 1
		if dist[r] > best_d:
			break
		for e in CData.adjacent(r):
			var m := int(e[0])
			if dist[m] >= 0:
				continue
			dist[m] = dist[r] + 1
			queue.append(m)
			if _retreat_ok(st, f, m, from) and (dist[m] < best_d or (dist[m] == best_d and m < best)):
				best = m
				best_d = dist[m]
	return best


static func _drop_empty_armies(st: Dictionary) -> void:
	var keep: Array = []
	for a in st["armies"]:
		if CState.unit_count(a) > 0:
			keep.append(a)
	st["armies"] = keep


# ------------------------------------------------------------- diplomacy ---

static func check_proposal(st: Dictionary, f: int, g: int, what: String) -> String:
	if g < 0 or g >= CState.nf() or g == f or not CState.alive(st, g):
		return "no such faction"
	if CState.is_human(st, g) and CState.is_human(st, f):
		return "you are allies"
	var d := CState.dip(st, f, g)
	match what:
		"peace":
			return "" if d == CState.WAR else "not at war"
		"trade":
			return "" if d == CState.PEACE else ("already trading" if d == CState.TRADE else "make peace first")
		"cancel_trade":
			return "" if d == CState.TRADE else "no trade agreement"
	return "unknown proposal"


static func _declare_war(st: Dictionary, f: int, g: int) -> String:
	if g < 0 or g >= CState.nf() or g == f or not CState.alive(st, g):
		return "no such faction"
	if CState.friendly(st, f, g):
		return "allies cannot go to war"
	if CState.dip(st, f, g) == CState.WAR:
		return "already at war"
	declare_war(st, f, g)
	return ""


static func declare_war(st: Dictionary, f: int, g: int) -> void:
	CState.set_dip(st, f, g, CState.WAR)
	event(st, {"k": "war", "a": f, "b": g})


static func make_peace(st: Dictionary, f: int, g: int) -> void:
	CState.set_dip(st, f, g, CState.PEACE)
	event(st, {"k": "peace", "a": f, "b": g})


static func _answer(st: Dictionary, f: int, id: int, accept: int) -> String:
	for p in st["proposals"]:
		if int(p["id"]) == id and int(p["to"]) == f:
			if accept != 0:
				var g := int(p["from"])
				if check_proposal(st, g, f, str(p["what"])) == "":
					apply_agreement(st, g, f, str(p["what"]))
			else:
				event(st, {"k": "refused", "from": f, "to": int(p["from"]), "what": str(p["what"])})
			st["proposals"].erase(p)
			return ""
	return "no such proposal"


static func apply_agreement(st: Dictionary, f: int, g: int, what: String) -> void:
	match what:
		"peace":
			make_peace(st, f, g)
		"trade":
			CState.set_dip(st, f, g, CState.TRADE)
			event(st, {"k": "trade", "a": f, "b": g})
		"cancel_trade":
			CState.set_dip(st, f, g, CState.PEACE)
			event(st, {"k": "trade_end", "a": f, "b": g})


# --------------------------------------------------------------- economy ---

## Income of faction f: {regions, trade, total} (per turn).
static func income(st: Dictionary, f: int) -> Dictionary:
	var reg := 0
	var markets := 0
	var owned := CState.regions_of(st, f)
	for r in owned:
		reg += region_income(st, r)
		markets += CState.building(st, r, CData.MARKET)
	var trade := 0
	for g in CState.nf():
		if g == f or not CState.alive(st, g):
			continue
		var d := CState.dip(st, f, g)
		if d == CState.TRADE or d == CState.ALLIED:
			var n := mini(owned.size(), CState.regions_of(st, g).size())
			trade += mini(CData.TRADE_CAP, CData.TRADE_BASE + CData.TRADE_PER_REGION * n)
	trade = trade * (100 + 15 * mini(markets, 3)) / 100
	# A large realm is costly to govern: income falls by CORRUPTION_PCT per
	# region beyond CORRUPTION_FREE (at most CORRUPTION_MAX).
	var corr := clampi((owned.size() - CData.CORRUPTION_FREE) * CData.CORRUPTION_PCT, 0, CData.CORRUPTION_MAX)
	var gross := reg + trade
	var cut := gross * corr / 100
	return {"regions": reg, "trade": trade, "corruption": cut, "total": gross - cut}


static func region_income(st: Dictionary, r: int) -> int:
	if not CState.siege_at(st, r).is_empty():
		return 0  # besieged: nothing comes in
	var rs: Dictionary = st["regions"][r]
	var inc := int(CData.REGIONS[r]["wealth"]) * CData.WEALTH_INCOME + int(CData.LEVEL_INCOME[int(rs["level"])]) \
		+ CState.building(st, r, CData.FARM) * CData.FARM_INCOME + CState.building(st, r, CData.MARKET) * CData.MARKET_INCOME
	if raider(st, r) >= 0:
		inc /= 2  # raided (version 5): half the income
	return inc


## Version 5: the faction raiding region r (its army stands there, at war
## with the owner, without a siege; the lowest army id), else -1.
static func raider(st: Dictionary, r: int) -> int:
	if not CState.moves_on(st) or not CState.siege_at(st, r).is_empty():
		return -1
	var o := CState.owner(st, r)
	if o < 0:
		return -1
	for a in st["armies"]:
		if int(a["r"]) == r and CState.at_war(st, int(a["f"]), o):
			return int(a["f"])
	return -1


static func upkeep(st: Dictionary, f: int) -> int:
	var u := 0
	for a in st["armies"]:
		if int(a["f"]) == f:
			for unit in a["units"]:
				u += CState.upkeep_of(CState.unit_type(unit))
	return u


static func growth_per_turn(st: Dictionary, r: int) -> int:
	return 1 + CState.building(st, r, CData.FARM) + (1 if int(CData.REGIONS[r]["wealth"]) >= 5 else 0)


## End of turn: buildings, recruits, money, desertion, replenishment,
## sieges, garrisons, growth; then flags reset.
static func end_of_turn(st: Dictionary) -> void:
	var nreg := CData.region_count()
	check_sieges(st)
	# Constructions and recruits.
	for r in nreg:
		var rs: Dictionary = st["regions"][r]
		var o := int(rs["owner"])
		var bld: Array = rs["build"]
		if not bld.is_empty() and CState.siege_at(st, r).is_empty():  # paused while besieged
			bld[2] = int(bld[2]) - 1
			if int(bld[2]) <= 0:
				CState._add_building(rs, int(bld[0]), int(bld[1]), 99)
				rs["build"] = []
				CState.record_built(st, r, int(bld[0]), int(bld[1]))
				event(st, {"k": "built", "r": r, "f": o, "chain": int(bld[0]), "level": int(bld[1])})
		var q: Array = rs["queue"]
		if not q.is_empty() and o >= 0:
			for key in q:
				_add_recruit(st, o, r, str(key))
			event(st, {"k": "recruited", "r": r, "f": o, "units": q.duplicate()})
			rs["queue"] = []
	# Money.
	for f in CState.nf():
		var fs: Dictionary = st["factions"][f]
		if int(fs["alive"]) == 0:
			continue
		var inc := int(income(st, f)["total"])
		var up := upkeep(st, f)
		fs["income"] = inc
		fs["upkeep"] = up
		fs["treasury"] = int(fs["treasury"]) + inc - up
		if int(fs["treasury"]) < 0:
			for a in st["armies"]:
				if int(a["f"]) == f:
					for unit in a["units"]:
						unit["n"] = maxi(int(unit["n"]) - maxi(int(unit["n"]) * CData.DEBT_DESERTION / 100, 1), 0)
			event(st, {"k": "debt", "f": f, "treasury": int(fs["treasury"])})
	for a in st["armies"]:
		var keep: Array = []
		for unit in a["units"]:
			if int(unit["n"]) > 0:
				keep.append(unit)
		a["units"] = keep
	_drop_empty_armies(st)
	# Replenishment in friendly land.
	for a in st["armies"]:
		var f := int(a["f"])
		var r := int(a["r"])
		if int(a["busy"]) != 0 or int(st["factions"][f]["treasury"]) < 0 or siege_role(st, a) != 0:
			continue
		if not CState.friendly(st, f, CState.owner(st, r)):
			continue
		for unit in a["units"]:
			var ty := CState.unit_type(unit)
			var full := UT.size_of(ty)
			var lvl := CState.building(st, r, int(CData.LINE_CHAIN[UT.line_of(ty)]))
			var add := full * (CData.REPLENISH_BASE + CData.REPLENISH_PER_LEVEL * lvl) / 100
			unit["n"] = mini(int(unit["n"]) + maxi(add, 1), full)
	# Sieges: supplies, starvation, surrender.
	_siege_turn(st)
	# Garrisons and growth (both stop while besieged).
	for r in nreg:
		var rs: Dictionary = st["regions"][r]
		var besieged := not CState.siege_at(st, r).is_empty()
		if CState.battle_at(st, r).is_empty() and not besieged:
			rs["gar"] = mini(int(rs["gar"]) + CData.GARRISON_REGEN, 100)
		if besieged:
			continue
		var lvl := int(rs["level"])
		rs["growth"] = int(rs["growth"]) + growth_per_turn(st, r)
		if lvl < CData.CITY and int(rs["growth"]) >= int(CData.GROWTH_TO[lvl + 1]):
			rs["level"] = lvl + 1
			CState.record_built(st, r, -1, lvl + 1)
			event(st, {"k": "grew", "r": r, "f": int(rs["owner"]), "level": lvl + 1})
	var free_moves := CState.moves_on(st)
	for a in st["armies"]:
		a["busy"] = 1 if in_battle(st, int(a["id"])) else 0
		if free_moves:
			a["idle"] = 0 if int(a["moved"]) != 0 else int(a.get("idle", 0)) + 1
			a["mp"] = CState.max_mp(a)
		a["moved"] = 0
		a["from"] = -1
	# Proposals last one turn.
	var keep_p: Array = []
	for p in st["proposals"]:
		if int(p["turn"]) >= int(st["turn"]):
			keep_p.append(p)
	st["proposals"] = keep_p


## New recruit: joins the faction's first army in the region with room, or
## forms a new army.
static func _add_recruit(st: Dictionary, f: int, r: int, key: String) -> void:
	var unit := {"t": key, "n": UT.size_of(UT.index_of(key))}
	for a in st["armies"]:
		if int(a["f"]) == f and int(a["r"]) == r and int(a["busy"]) == 0 and CState.unit_count(a) < CData.ARMY_MAX:
			(a["units"] as Array).append(unit)
			return
	var id := new_army_id(st, f)
	st["factions"][f]["next_army"] = int(st["factions"][f]["next_army"]) + 1
	_insert_army(st, {"id": id, "f": f, "r": r, "units": [unit], "from": -1, "moved": 0, "busy": 0})


# ------------------------------------------------------ end conditions ---

static func check_eliminations(st: Dictionary) -> void:
	for f in CState.nf():
		var fs: Dictionary = st["factions"][f]
		if int(fs["alive"]) == 0:
			continue
		if not CState.regions_of(st, f).is_empty():
			continue
		fs["alive"] = 0
		var keep: Array = []
		for a in st["armies"]:
			if int(a["f"]) != f:
				keep.append(a)
		st["armies"] = keep
		var kp: Array = []
		for p in st["proposals"]:
			if int(p["from"]) != f and int(p["to"]) != f:
				kp.append(p)
		st["proposals"] = kp
		event(st, {"k": "eliminated", "f": f})
	# Battles whose attackers are all gone end: the defenders hold.
	var keepb: Array = []
	for b in st["battles"]:
		var arm := battle_armies(st, b)
		var att_here := false
		for a in arm[0]:
			if int(a["r"]) == int(b["r"]):
				att_here = true
		if att_here:
			keepb.append(b)
		else:
			for s in 2:
				for a in arm[s]:
					a["busy"] = 0
	st["battles"] = keepb


## Players' progress toward victory: {regions, capitals, need_regions,
## need_capitals}.
static func victory_progress(st: Dictionary) -> Dictionary:
	var regions := 0
	var caps := 0
	for r in CData.region_count():
		if CState.is_human(st, CState.owner(st, r)):
			regions += 1
			if CData.KEY_CITIES.has(str(CData.REGIONS[r]["key"])):
				caps += 1
	return {"regions": regions, "capitals": caps,
		"need_regions": int(st["settings"]["victory_regions"]),
		"need_capitals": int(st["settings"]["victory_capitals"])}


static func check_victory(st: Dictionary) -> void:
	if int(st["winner"]) >= 0 or (st["humans"] as Array).is_empty():
		return
	for h in st["humans"]:
		if not CState.alive(st, int(h)):
			st["winner"] = 0
			st["phase"] = "over"
			event(st, {"k": "defeat", "f": int(h)})
			return
	var p := victory_progress(st)
	if int(p["regions"]) >= int(p["need_regions"]) and int(p["capitals"]) >= int(p["need_capitals"]):
		st["winner"] = 1
		st["phase"] = "over"
		event(st, {"k": "victory"})


static func event(st: Dictionary, e: Dictionary) -> void:
	e["turn"] = int(st["turn"])
	(st["events"] as Array).append(e)
