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
##        (version 6: "x", "y" the destination cell, or "tgt" an enemy army;
##        "to" still means that region's settlement; see "the continuous
##        overworld (v6)" at the end of this file)
##   {"t": "assault", "r": region}  (version 4: the besiegers storm it;
##        version 5 also from inside the region without a siege)
##   {"t": "sally", "r": region}    (version 4: the besieged ride out)
##   {"t": "siege", "r": region}    (version 5: lay siege from inside)
##   {"t": "stance", "a": army id, "s": 0 field | 1 inside the walls} (v5;
##        version 6: CData.ST_* default 0, forced march 2, fortify 3, raid 4)
##   {"t": "cancel_move", "army": id}  (version 5: forget a stored dest)
##   {"t": "recruit", "r": region, "unit": unit type key}
##        (version 6 also "army": id, into that army of ours standing on or
##        next to the settlement, or "new": 1, the turn's recruits raise one
##        new army inside the walls; an army with recruits queued for it is
##        mustering: it cannot march this turn; see _recruit)
##   {"t": "build", "r": region, "chain": building chain index}
##   {"t": "merge", "army": id, "into": id}             (same region;
##        version 6: on the same or a neighbouring cell)
##   {"t": "split", "army": id, "units": [unit indices], "new": new army id}
##   {"t": "disband", "army": id, "units": [unit indices]}
##   {"t": "exchange", "from": id, "to": id, "units": [indices of from's
##        units that go to `to`], "back": [indices of to's units that come
##        to `from`] (optional)}: armies standing together (as merge) trade
##        units; neither may end above CData.ARMY_MAX; an army left with no
##        units is gone. `to` may be an allied human's army: a gift (no
##        "back": taking is not allowed); event "gift" for the receiver.
##   {"t": "arrange", "army": id, "order": [unit indices]}: the army's units
##        in a new order, a permutation of 0..n-1 (the new list's unit k is
##        the old unit order[k]); any format; an army of the faction not in
##        a battle. The order sets the order its units take the field in
##        (cbattle.build reads the list in order).
##   Version 6 move with "join": id (another army of the faction) instead of
##        x, y / tgt: march to it and merge into it on arrival (it keeps its
##        id, stance and cell); with persist the army keeps following it
##        (army key "dest_army") until it merges or the army is gone.
##   {"t": "propose", "to": faction, "what": "peace" | "trade" | "cancel_trade" | "team"}
##        ("team": join my team; an AI answers by CAI.why at once, a human
##        gets a proposal to answer next turn; see "teams" below)
##   {"t": "leave_team"}                                (a player; notice turns)
##   {"t": "war", "to": faction}                        (declare war)
##   {"t": "answer", "id": proposal id, "accept": 0 | 1}
## Gifts between the human players (allied, both alive; see "gifts between
## players" below; the AI never issues or receives these):
##   {"t": "gift_region", "r": region, "to": faction, "price": n}: price 0
##        hands the city over at once; price > 0 is an offer the receiver
##        accepts next turn (a proposal, kind "offer_city")
##   {"t": "buy_region", "r": region, "price": n}: an offer to buy the
##        allied player's city r (a proposal, kind "ask_city")
##   {"t": "gift_money", "to": faction, "amount": n}
##   {"t": "accept_offer", "id": proposal id} / {"t": "decline_offer", "id"}
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
## garrison, unit = index in the garrison list; a fought battle's rows also
## carry "kills", the enemies the unit's men killed: for the battle screen,
## never read by the rules), garrison_pct: garrison strength left (%)}.

const CData := preload("res://campaign/cdata.gd")
const CState := preload("res://campaign/cstate.gd")
const UT := preload("res://sim/unit_types.gd")
const CChars := preload("res://campaign/cchars.gd")


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
			if CState.grid_on(st):
				var ma := CState.army(st, int(o.get("army", -1)))
				if ma.is_empty() or int(ma["f"]) != f:
					return "no such army"
				if mustering(st, int(ma["id"])):
					return "mustering"
				return _can_move6(st, ma, order_cell(st, ma, o), int(o.get("tgt", -1)), int(o.get("mode", CData.MODE_SIEGE)),
					true, int(o.get("join", -1)))
			return can_move(st, CState.army(st, int(o.get("army", -1))), int(o.get("to", -1)), f)
		"build":
			return _build(st, f, int(o.get("r", -1)), int(o.get("chain", -1)))
		"recruit":
			return _recruit(st, f, o)
		"recruit_char":
			return CChars.recruit(st, f, o)
		"attach":
			return CChars.attach(st, f, o)
		"detach":
			return CChars.detach(st, f, o)
		"merge":
			return _merge(st, f, int(o.get("army", -1)), int(o.get("into", -1)))
		"split":
			return _split(st, f, int(o.get("army", -1)), o.get("units", []), int(o.get("new", -1)))
		"disband":
			return _disband(st, f, int(o.get("army", -1)), o.get("units", []))
		"exchange":
			return _exchange(st, f, int(o.get("from", -1)), int(o.get("to", -1)), o.get("units", []), o.get("back", []))
		"arrange":
			return _arrange(st, f, int(o.get("army", -1)), o.get("order", []))
		"propose":
			return check_proposal(st, f, int(o.get("to", -1)), str(o.get("what", "")))
		"leave_team":
			return _leave_team(st, f)
		"war":
			return _declare_war(st, f, int(o.get("to", -1)))
		"answer":
			return _answer(st, f, int(o.get("id", -1)), int(o.get("accept", 0)))
		"gift_region":
			return _gift_region(st, f, int(o.get("r", -1)), int(o.get("to", -1)), int(o.get("price", 0)))
		"buy_region":
			return _buy_region(st, f, int(o.get("r", -1)), int(o.get("price", 0)))
		"gift_money":
			return _gift_money(st, f, int(o.get("to", -1)), int(o.get("amount", 0)))
		"accept_offer":
			return _answer_offer(st, f, int(o.get("id", -1)), true)
		"decline_offer":
			return _answer_offer(st, f, int(o.get("id", -1)), false)
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
				"ok": why == "", "why": why, "ak": ammo_for(st, f, r, key)})
	return out


## The special ammunition kind (its key, "" none) a unit of type `key`
## recruited by faction f in region r carries: the first CData.AMMO_AVAIL
## row riding on its weapon that lists the faction and whose building
## stands in r at its level. (Stored on the unit entry as "ak".)
static func ammo_for(st: Dictionary, f: int, r: int, key: String) -> String:
	var ty := UT.index_of(key)
	if ty < 0 or f < 0 or f >= CData.FACTIONS.size() or r < 0 or UT.stat(ty, "m_ak") < 0:
		return ""
	var fk := str(CData.FACTIONS[f]["key"])
	for row in CData.AMMO_AVAIL:
		var k := UT.ammo_index(str(row[0]))
		if k < 0 or UT.ammo_stat(k, "base") != UT.stat(ty, "m_ak") or not (row[1] as Array).has(fk):
			continue
		if CState.building(st, r, int(row[2])) >= int(row[3]):
			return str(row[0])
	return ""


## A new unit entry of type `key` raised by faction f in region r (full
## strength; its special ammunition kind, if any, as "ak").
static func new_unit(st: Dictionary, f: int, r: int, key: String) -> Dictionary:
	var unit := {"t": key, "n": UT.size_of(UT.index_of(key))}
	var ak := ammo_for(st, f, r, key)
	if ak != "":
		unit["ak"] = ak
	return unit


## Level of the building needed for a unit type (chain, level).
static func needs(key: String) -> Array:
	if CData.UNIT_NEEDS.has(key):
		return CData.UNIT_NEEDS[key][0]
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
	for nd2 in CData.UNIT_NEEDS.get(key, []):
		if CState.building(st, r, int(nd2[0])) < int(nd2[1]):
			return "needs %s %d" % [CData.CHAINS[int(nd2[0])]["name"], int(nd2[1])]
	if (rs["queue"] as Array).size() >= int(CData.RECRUITS_PER_TURN[int(rs["level"])]):
		return "recruitment full this turn"
	if CState.is_general(key):
		for k in rs["queue"]:
			if CState.is_general(str(k)):
				return "a general is already raised here this turn"
	if not CState.battle_at(st, r).is_empty():
		return "battle pending here"
	if UT.price_of(ty) > int(st["factions"][f]["treasury"]):
		return "not enough money"
	return ""


## A recruit order: {r, unit} (the old form: the recruit joins the army
## _add_recruit picks), version 6 also {r, unit, army: id} (into that army
## of ours on or next to the settlement) or {r, unit, new: 1} (the
## recruits of the turn raise one new army inside the walls). Version 6
## records for each queue entry the army it joins in the region's "qa"
## (parallel to "queue": an army id, QA_RAISE for a "new" order, QA_ANY for
## an old-form order that found no army; only present during a turn's
## resolution): that army is mustering and cannot march this turn.
const QA_ANY := -1
const QA_RAISE := -2


static func _recruit(st: Dictionary, f: int, o: Dictionary) -> String:
	var r := int(o.get("r", -1))
	var key := str(o.get("unit", ""))
	var army := int(o.get("army", -1))
	var raise := int(o.get("new", 0)) != 0
	var why := recruit_order_check(st, f, r, key, army, raise)
	if why != "":
		return why
	var into := -1
	if CState.grid_on(st):
		into = army if army >= 0 else (QA_RAISE if raise else recruit_target(st, f, r, key))
	st["factions"][f]["treasury"] = int(st["factions"][f]["treasury"]) - UT.price_of(UT.index_of(key))
	var rs: Dictionary = st["regions"][r]
	(rs["queue"] as Array).append(key)
	if CState.grid_on(st):
		if not rs.has("qa"):
			rs["qa"] = []
		(rs["qa"] as Array).append(into)
	return ""


## recruit_check plus the version 6 targets: army (an army of ours on or
## next to the settlement, not in a battle, with room for the recruits
## already queued for it) or raise (a new army). Older formats refuse both.
static func recruit_order_check(st: Dictionary, f: int, r: int, key: String, army: int = -1, raise: bool = false) -> String:
	if (army >= 0 or raise) and not CState.grid_on(st):
		return "bad order"
	if army >= 0 and raise:
		return "bad order"
	var why := recruit_check(st, f, r, key)
	if why != "" or army < 0:
		return why
	return army_recruit_check(st, f, r, army, key)


## "" if army id of faction f can take recruits from region r this turn
## (version 6): it stands on or next to the settlement's cell, is not in a
## battle and has room (its units plus the recruits already queued for it
## below CData.ARMY_MAX); a general (key, when given) only into an army
## without one, none queued for it. The region's own checks are
## recruit_check's.
static func army_recruit_check(st: Dictionary, f: int, r: int, id: int, key: String = "") -> String:
	var a := CState.army(st, id)
	if a.is_empty() or int(a["f"]) != f:
		return "no such army"
	if r < 0 or r >= CData.region_count() or CGrid.cheb(CState.cell(a), CGrid.site(r)) > 1:
		return "not at the settlement"
	if int(a["busy"]) != 0:
		return "in a battle"
	if CState.unit_count(a) + queued_into(st, id) >= CData.ARMY_MAX:
		return "the army is full"
	if key != "" and CState.is_general(key) and (CState.generals(a) > 0 or generals_queued_into(st, id) > 0):
		return "the army already has a general"
	return ""


## General recruits queued this turn (all regions) that join army id.
static func generals_queued_into(st: Dictionary, id: int) -> int:
	var n := 0
	for rs in st["regions"]:
		if rs.has("qa"):
			var q: Array = rs["queue"]
			var qa: Array = rs["qa"]
			for k in mini(q.size(), qa.size()):
				if int(qa[k]) == id and CState.is_general(str(q[k])):
					n += 1
	return n


## Version 6: the settlement of faction f (a region it owns) army a stands
## on or next to, -1 if none (allied settlements do not recruit for it).
static func recruit_region(st: Dictionary, a: Dictionary) -> int:
	if a.is_empty() or not CState.grid_on(st):
		return -1
	var c := CState.cell(a)
	for r in CData.region_count():
		if int(st["regions"][r]["owner"]) == int(a["f"]) and CGrid.cheb(c, CGrid.site(r)) <= 1:
			return r
	return -1


## Recruits queued this turn (all regions) that join army id.
static func queued_into(st: Dictionary, id: int) -> int:
	var n := 0
	for rs in st["regions"]:
		if rs.has("qa"):
			for v in rs["qa"]:
				if int(v) == id:
					n += 1
	return n


## Version 6 mustering rule: an army with recruits queued for it this turn
## cannot march this turn (its move is refused, "mustering"; a stored
## march carries on next turn).
static func mustering(st: Dictionary, id: int) -> bool:
	return id >= 0 and queued_into(st, id) > 0


## The queue entries of region r as [[unit key, army id | QA_RAISE |
## QA_ANY], ...] (older formats: QA_ANY for all).
static func queue_of(st: Dictionary, r: int) -> Array:
	var rs: Dictionary = st["regions"][r]
	var q: Array = rs["queue"]
	var qa: Array = rs.get("qa", [])
	var out: Array = []
	for k in q.size():
		out.append([str(q[k]), int(qa[k]) if k < qa.size() else QA_ANY])
	return out


## Version 6: the army an old-form recruit in region r joins (where
## _add_recruit would place it now, counting the recruits already queued
## for each army): the first army of f by id on or next to the
## settlement's cell, not in a battle, with room; QA_ANY if none (placed
## by _add_recruit at the end of the turn: usually a new army inside the
## walls). A general (key) only joins an army without one.
static func recruit_target(st: Dictionary, f: int, r: int, key: String = "") -> int:
	var site := CGrid.site(r)
	var gen := key != "" and CState.is_general(key)
	for a in st["armies"]:
		if int(a["f"]) == f and CGrid.cheb(CState.cell(a), site) <= 1 and int(a["busy"]) == 0 \
				and CState.unit_count(a) + queued_into(st, int(a["id"])) < CData.ARMY_MAX \
				and (not gen or (CState.generals(a) == 0 and generals_queued_into(st, int(a["id"])) == 0)):
			return int(a["id"])
	return QA_ANY


static func _own_free_army(st: Dictionary, f: int, id: int) -> Dictionary:
	var a := CState.army(st, id)
	if a.is_empty() or int(a["f"]) != f or int(a["busy"]) != 0 or siege_role(st, a) != 0:
		return {}
	return a


## "" if armies a and b stand together to merge or trade units: neither in
## a battle; version 6 on the same or neighbouring cells (an army inside a
## besieged settlement only with another inside it; besiegers may); older
## formats in the same region and neither in a siege.
static func together(st: Dictionary, a: Dictionary, b: Dictionary) -> String:
	if int(a["busy"]) != 0 or int(b["busy"]) != 0:
		return "in a battle"
	if CState.grid_on(st):
		if CGrid.cheb(CState.cell(a), CState.cell(b)) > 1:
			return "not together"
		if (siege_role(st, a) == 2 or siege_role(st, b) == 2) and CState.cell(a) != CState.cell(b):
			return "besieged"
		return ""
	if siege_role(st, a) != 0 or siege_role(st, b) != 0:
		return "in a siege"
	if int(a["r"]) != int(b["r"]):
		return "not in the same region"
	return ""


## "" if army id of faction f may merge into army `into` now (version 6
## rules; older formats: _merge's own checks).
static func merge_check(st: Dictionary, f: int, id: int, into: int) -> String:
	var a := CState.army(st, id)
	var b := CState.army(st, into)
	if a.is_empty() or b.is_empty() or id == into or int(a["f"]) != f or int(b["f"]) != f:
		return "no such army"
	var why := together(st, a, b)
	if why != "":
		return why
	if CState.unit_count(a) + CState.unit_count(b) > CData.ARMY_MAX:
		return "more than %d units" % CData.ARMY_MAX
	if CChars.merge_conflict(st, id, into):
		return "both armies have a hero, assassin or diplomat of the same kind"
	return ""


## One general an army (docs/CAMPAIGN.md "The general"): when units come
## together (merge, exchange, recruits placed), every general unit after
## the army's first becomes a plain bodyguard (UnitTypes "bodyguard": the
## same riders, no command aura). Recruiting refuses a second outright.
static func _one_general(a: Dictionary) -> void:
	var seen := false
	for u in a["units"]:
		if CState.is_general(str(u["t"])):
			if seen:
				u["t"] = PLAIN_GUARD
			seen = true


const PLAIN_GUARD := "bodyguard"


## Army a joins army b: its units after b's, b keeps its id, stance and
## cell and moves at the pace of the slower part; a is gone. (A second
## general becomes a plain bodyguard.)
static func _absorb(st: Dictionary, b: Dictionary, a: Dictionary) -> void:
	CChars.transfer(st, int(a["id"]), int(b["id"]))
	(b["units"] as Array).append_array(a["units"])
	_one_general(b)
	if CState.moves_on(st):
		b["mp"] = mini(mini(CState.mp(a), CState.mp(b)), CState.full_mp(st, b))
		b["moved"] = maxi(int(a["moved"]), int(b["moved"]))
	st["armies"].remove_at(CState.army_index(st, int(a["id"])))


static func _merge(st: Dictionary, f: int, id: int, into: int) -> String:
	if CState.grid_on(st):
		var why := merge_check(st, f, id, into)
		if why == "":
			_absorb(st, CState.army(st, into), CState.army(st, id))
		return why
	var a := _own_free_army(st, f, id)
	var b := _own_free_army(st, f, into)
	if a.is_empty() or b.is_empty() or id == into:
		return "no such army"
	if CState.grid_on(st):
		if CGrid.cheb(CState.cell(a), CState.cell(b)) > 1:
			return "not together"
	elif int(a["r"]) != int(b["r"]):
		return "not in the same region"
	if CState.unit_count(a) + CState.unit_count(b) > CData.ARMY_MAX:
		return "more than %d units" % CData.ARMY_MAX
	if CChars.merge_conflict(st, id, into):
		return "both armies have a hero, assassin or diplomat of the same kind"
	CChars.transfer(st, id, into)
	(b["units"] as Array).append_array(a["units"])
	_one_general(b)
	if CState.moves_on(st):
		# The merged army moves at the pace of its slower part.
		b["mp"] = mini(mini(CState.mp(a), CState.mp(b)), CState.full_mp(st, b))
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
	if CState.grid_on(st):
		na["x"] = int(a["x"])
		na["y"] = int(a["y"])
		na["dest_x"] = -1
		na["dest_y"] = -1
		na["stance"] = CState.stance(a)
		na["mp"] = mini(CState.mp(a), CState.full_mp(st, na))
		a["mp"] = mini(CState.mp(a), CState.full_mp(st, a))
	elif CState.moves_on(st):
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
		CChars.release(st, a)
		st["armies"].remove_at(CState.army_index(st, id))
	return ""


## idx is a valid list of distinct unit indices of army a (empty is valid).
static func _idx_ok(a: Dictionary, idx) -> bool:
	return idx is Array and _unit_list(a, idx).size() == (idx as Array).size()


## A gift: army b belongs to an allied human faction (not f's own).
static func is_gift(_st: Dictionary, f: int, b: Dictionary) -> bool:
	return not b.is_empty() and int(b["f"]) != f


## "" if faction f may trade units between its army `from` and army `to`
## (its own, or an allied human's: a gift, nothing taken back): units
## [indices of from's units] go to `to`, back [indices of to's units] come
## to `from`; both armies together (as merge); neither above ARMY_MAX.
static func exchange_check(st: Dictionary, f: int, from: int, to: int, units, back = []) -> String:
	var a := CState.army(st, from)
	var b := CState.army(st, to)
	if a.is_empty() or b.is_empty() or from == to or int(a["f"]) != f:
		return "no such army"
	var g := int(b["f"])
	if g != f and not (CState.is_human(st, f) and CState.is_human(st, g) and CState.friendly(st, f, g) and CState.alive(st, g)):
		return "not a friendly army"
	var why := together(st, a, b)
	if why != "":
		return why
	if not _idx_ok(a, units) or not _idx_ok(b, back):
		return "bad units"
	var nu := (units as Array).size()
	var nbk := (back as Array).size()
	if nu == 0 and nbk == 0:
		return "no units chosen"
	if g != f and nbk > 0:
		return "cannot take an ally's units"
	if CState.unit_count(a) - nu + nbk > CData.ARMY_MAX or CState.unit_count(b) - nbk + nu > CData.ARMY_MAX:
		return "more than %d units" % CData.ARMY_MAX
	return ""


static func _exchange(st: Dictionary, f: int, from: int, to: int, units, back) -> String:
	var why := exchange_check(st, f, from, to, units, back)
	if why != "":
		return why
	var a := CState.army(st, from)
	var b := CState.army(st, to)
	var out := _unit_list(a, units)
	var bk := _unit_list(b, back)
	var give: Array = []
	var keep_a: Array = []
	for k in CState.unit_count(a):
		(give if out.has(k) else keep_a).append(a["units"][k])
	var take: Array = []
	var keep_b: Array = []
	for k in CState.unit_count(b):
		(take if bk.has(k) else keep_b).append(b["units"][k])
	var mpa := CState.mp(a)
	var mpb := CState.mp(b)
	a["units"] = keep_a + take
	b["units"] = keep_b + give
	_one_general(a)
	_one_general(b)
	if CState.moves_on(st):
		# A receiving army moves at the pace of the slower part.
		if not give.is_empty():
			b["mp"] = mini(mpa, mpb)
			b["moved"] = maxi(int(a["moved"]), int(b["moved"]))
		if not take.is_empty():
			a["mp"] = mini(mpa, mpb)
			a["moved"] = maxi(int(a["moved"]), int(b["moved"]))
		a["mp"] = mini(CState.mp(a), CState.full_mp(st, a))
		b["mp"] = mini(CState.mp(b), CState.full_mp(st, b))
	if is_gift(st, f, b):
		event(st, {"k": "gift", "f": f, "to": int(b["f"]), "r": int(b["r"]), "n": give.size(), "army": to})
	for id in [from, to]:
		var x := CState.army(st, id)
		if not x.is_empty() and CState.unit_count(x) == 0:
			st["armies"].remove_at(CState.army_index(st, id))
	return ""


## "" if faction f may put the units of its army id in the order `order`
## (a permutation of the unit indices, see "arrange" above).
static func arrange_check(st: Dictionary, f: int, id: int, order) -> String:
	var a := CState.army(st, id)
	if a.is_empty() or int(a["f"]) != f:
		return "no such army"
	if int(a["busy"]) != 0:
		return "in a battle"
	var n := CState.unit_count(a)
	if not (order is Array) or (order as Array).size() != n:
		return "bad order"
	var seen: Array = []
	seen.resize(n)
	seen.fill(0)
	for v in order:
		if not (v is int or v is float):
			return "bad order"
		var k := int(v)
		if k < 0 or k >= n or float(k) != float(v) or int(seen[k]) != 0:
			return "bad order"
		seen[k] = 1
	return ""


static func _arrange(st: Dictionary, f: int, id: int, order) -> String:
	var why := arrange_check(st, f, id, order)
	if why != "":
		return why
	var a := CState.army(st, id)
	var old: Array = a["units"]
	var units: Array = []
	for v in order:
		units.append(old[int(v)])
	a["units"] = units
	return ""


static func _insert_army(st: Dictionary, a: Dictionary) -> void:
	if CState.grid_on(st):
		CState.army_defaults6(a)
	elif CState.moves_on(st):
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
	if CState.grid_on(st):
		if to < 0 or to >= CData.region_count():
			return "no route"
		return _can_move6(st, a, CGrid.site(to))
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
	if CState.grid_on(st):
		return _move_targets6(st, a, this_turn)
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
	if CState.grid_on(st):
		var sc := CGrid.site(r)
		b["x"] = CGrid.cx(sc)
		b["y"] = CGrid.cy(sc)
		b["app"] = -1
		b["edge"] = []
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
## Version 6: its armies on the ring of r's settlement (not on a forced
## march).
static func _mine_here(st: Dictionary, f: int, r: int) -> Array:
	var out: Array = []
	if CState.grid_on(st):
		for a in on_ring(st, r, f):
			if int(a["busy"]) == 0 and CState.stance(a) != CData.ST_FORCED:
				out.append(a)
		return out
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
	if CState.grid_on(st):
		var a: Dictionary = _mine_here(st, f, r)[0]
		start_siege(st, r, a, int(a["from"]))
		return ""
	_act_here(st, _mine_here(st, f, r)[0], CData.MODE_SIEGE)
	return ""


## Stance order (version 5): 1 inside the walls of a settlement of our side,
## 0 in the field. Taking the field where enemy armies stand rides out to
## fight them (a field battle). No points spent.
static func _set_stance(st: Dictionary, f: int, id: int, s: int) -> String:
	if not CState.moves_on(st):
		return "no free movement in this campaign"
	if CState.grid_on(st):
		return _set_stance6(st, f, id, s)
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
	if CState.grid_on(st):
		_drop_march(a)
		return ""
	a["dest"] = -1
	a["mode"] = CData.MODE_MARCH
	return ""


## Version 5: armies left in the land of a faction they are at peace with
## (peace made while they stood there) go home; armies inside the walls of
## a settlement no longer their side's take the field.
static func _check_trespass(st: Dictionary) -> void:
	if CState.grid_on(st):
		_check_trespass6(st)
		return
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
	if CState.grid_on(st):
		var c := CState.cell(a)
		var af2 := int(a["f"])
		for sg2 in st["sieges"]:
			var r2 := int(sg2["r"])
			var s2 := CGrid.site(r2)
			var o2 := CState.owner(st, r2)
			if c == s2 and CState.friendly(st, af2, o2):
				return 2
			if c != s2 and CGrid.cheb(c, s2) <= 1 and CState.friendly(st, af2, int(sg2["f"])) and CState.at_war(st, af2, o2):
				return 1
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
	if CState.grid_on(st):
		for a in on_ring(st, r, int(sg["f"]), true):
			if CState.at_war(st, int(a["f"]), o):
				out.append(a)
		return out
	for a in st["armies"]:
		if int(a["r"]) == r and CState.friendly(st, int(a["f"]), int(sg["f"])) and CState.at_war(st, int(a["f"]), o):
			out.append(a)
	return out


## Armies of the owner's side inside besieged region r (by id).
static func besieged_armies(st: Dictionary, r: int) -> Array:
	var out: Array = []
	if CState.siege_at(st, r).is_empty():
		return out
	if CState.grid_on(st):
		return inside_of(st, r)
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
	var ins := besieged_armies(st, r)
	var mine := f == o
	for a in ins:
		if int(a["f"]) == f:
			mine = true
	if not mine:
		return "none of your armies are inside"
	if not CState.battle_at(st, r).is_empty():
		return "battle pending there"
	if ins.is_empty() and int(st["regions"][r]["gar"]) <= 0:
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
	if CState.grid_on(st):
		if CState.siege_at(st, r).is_empty():
			_assault6(st, r, _mine_here(st, f, r)[0])
		else:
			_siege_battle6(st, r, "assault", {})
		return ""
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
	if CState.grid_on(st):
		var bs := besiegers(st, r)
		_siege_battle6(st, r, "sally", {}, CState.cell(bs[0]) if not bs.is_empty() else -1)
		return ""
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
			if CState.grid_on(st):
				# Version 6: the besiegers live off a stripped land too.
				for a in besiegers(st, r):
					for unit in a["units"]:
						unit["n"] = maxi(int(unit["n"]) - maxi(int(unit["n"]) * CData.SIEGE_BESIEGER_PCT / 100, 1), 0)
					var keep2: Array = []
					for unit in a["units"]:
						if int(unit["n"]) > 0:
							keep2.append(unit)
					a["units"] = keep2
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
	if CState.grid_on(st):
		_support6(st, b, counts, leads)
		return
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
	CChars.track(st)  # (the characters stand where their armies do, before any is lost)
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
	# Heroes and agents: the fallen are wounded; prisoners are ransomed.
	for ce in outcome.get("chars", []):
		if int(ce.get("alive", 1)) == 0:
			CChars.wound(st, int(ce["id"]))
	var pris: Array = outcome.get("prisoners", [])
	if pris.size() >= 2:
		CChars.add_ransom(st, int(b["att_f"]), int(pris[0]))
		CChars.add_ransom(st, int(b["def_f"]), int(pris[1]))
	var rs: Dictionary = st["regions"][r]
	if not open_field:
		rs["gar"] = clampi(int(outcome.get("garrison_pct", rs["gar"])), 0, 100)
	# Reinforcements stay where they are; armies in the region retreat if
	# their side lost.
	var loser := 1 - winner
	var bc := CGrid.at(int(b["x"]), int(b["y"])) if b.has("x") else -1
	var app := int(b.get("app", -1))
	if app >= 0 and loser == 1:
		app = (app + 4) % 8  # the defenders fall back away from the attackers
	for a in arm[loser]:
		a["busy"] = 0
		if (b["reinf"] as Array).has(int(a["id"])):
			continue
		if CState.grid_on(st) and not open_field and not field and loser == 1 and not inside(st, a):
			# Version 6: the owner's field armies beaten at the walls fall back.
			_retreat(st, a, -1, true, bc, app)
			continue
		if open_field:
			# Back along the way it came, else the nearest friendly region.
			_retreat(st, a, _origin(st, b, a), true, bc, app)
			continue
		if field:
			if loser == 0:
				# The siege is broken: the besiegers fall back to where they
				# came from, else to the nearest friendly region.
				_retreat(st, a, _origin(st, b, a), true, bc, app)
			elif _arrived(b, a) or (CState.grid_on(st) and not inside(st, a)):
				_retreat(st, a, _origin(st, b, a), false, bc, app)  # the relief is beaten off
			continue  # the armies inside stay behind their walls
		_retreat(st, a, _origin(st, b, a) if loser == 0 else -1, false, bc, app)
	for a in arm[winner]:
		a["busy"] = 0
	var new_owner := -1
	if open_field:
		st["battles"].erase(b)
		if winner == 0 and not CState.grid_on(st):
			_after_field_win(st, r, arm[0])
	if winner == 0 and not field and not open_field:
		# The attackers take the settlement: the lead attacker if it still
		# has an army in the region, else the first attacking army there.
		var lead := int(b["att_f"])
		var present := -1
		for a in arm[0]:
			if int(a["r"]) == r or (CState.grid_on(st) and CGrid.cheb(CState.cell(a), CGrid.site(r)) <= 1):
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
	CChars.sweep(st)
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
	rs.erase("qa")
	rs.erase("cq")
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
		var olds: Array = CState.armies_in(st, r)
		if CState.grid_on(st):
			olds = []
			for a in st["armies"]:
				if CState.cell(a) == CGrid.site(r):
					olds.append(a)
		for a in olds:
			if int(a["busy"]) == 0 and not CState.friendly(st, int(a["f"]), f):
				_retreat(st, a, -1, false, CGrid.site(r) if CState.grid_on(st) else -1)


## Move a beaten army to a neighbouring friendly region (its origin if
## given and still friendly; else land before sea, lowest index), or
## destroy it. far: with no friendly neighbour, the nearest friendly region
## (breadth first over land routes and sea lanes, lowest index first).
static func _retreat(st: Dictionary, a: Dictionary, prefer: int, far: bool = false, bc: int = -1, app: int = -1) -> void:
	if CState.grid_on(st):
		_retreat6(st, a, bc, app, far)
		return
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
	if CState.friendly(st, f, g):
		return "you are allies" if what != "team" else "you are on one team"
	var d := CState.dip(st, f, g)
	match what:
		"team":
			return team_merge_check(st, f, g)
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
		if int(p["id"]) == id and int(p["to"]) == f and not p.has("kind"):
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
		"team":
			merge_teams(st, f, g)


# ------------------------------------------------------------- teams ---
# Version 7. Factions with one id in the state's "teams" are on one team:
# friendly (CState.friendly: movement through each other's land,
# replenishment there, support in battle, joining each other's battles),
# never at war, one victory. Their dip is kept ALLIED. Joining: the "team"
# proposal (an AI answers by CAI.why); leaving: the "leave_team" order, with
# a notice of TEAM_NOTICE_TURNS turns, then a fresh team id and PEACE with
# the old mates.

const TEAM_NOTICE_TURNS := 2


## "" if the teams of f and g may merge now: no battle pending and no siege
## between them (a siege or a battle across the two teams).
static func team_merge_check(st: Dictionary, f: int, g: int) -> String:
	var tf := CState.team(st, f)
	var tg := CState.team(st, g)
	if tf == tg:
		return "you are on one team"
	for b in st["battles"]:
		var seen := [false, false]
		for side in battle_factions(st, b):
			for m in side:
				if CState.team(st, m) == tf:
					seen[0] = true
				elif CState.team(st, m) == tg:
					seen[1] = true
		if seen[0] and seen[1]:
			return "a battle is pending between the teams"
	for sg in st["sieges"]:
		var bf := CState.team(st, int(sg["f"]))
		var ow := CState.owner(st, int(sg["r"]))
		if ow >= 0 and ((bf == tf and CState.team(st, ow) == tg) or (bf == tg and CState.team(st, ow) == tf)):
			return "a siege is on between the teams"
	return ""


## The smaller team (members) joins the larger; a tie: f's team is the
## larger. Wars between the two end (dip ALLIED for every pair across).
static func merge_teams(st: Dictionary, f: int, g: int) -> void:
	var tf := CState.team(st, f)
	var tg := CState.team(st, g)
	if tf == tg:
		return
	var mf := CState.team_members(st, tf)
	var mg := CState.team_members(st, tg)
	var big := tf
	var small := tg
	var movers := mg
	if mg.size() > mf.size():
		big = tg
		small = tf
		movers = mf
	for m in movers:
		st["teams"][m] = big
	for a in CState.nf():
		for b in range(a + 1, CState.nf()):
			if CState.team(st, a) == big and CState.team(st, b) == big and CState.dip(st, a, b) != CState.ALLIED:
				CState.set_dip(st, a, b, CState.ALLIED)
	if st.has("leaving"):
		var kl: Array = []
		for e in st["leaving"]:
			if not movers.has(int(e[0])):
				kl.append(e)
		_set_leaving(st, kl)
	event(st, {"k": "team_joined", "from": f, "to": g, "team": big, "was": small, "members": movers.duplicate()})


static func _set_leaving(st: Dictionary, l: Array) -> void:
	if l.is_empty():
		st.erase("leaving")
	else:
		st["leaving"] = l


## Turn faction f gave notice of leaving its team (-1: not leaving).
static func leaving_since(st: Dictionary, f: int) -> int:
	for e in st.get("leaving", []):
		if int(e[0]) == f:
			return int(e[1])
	return -1


static func _leave_team(st: Dictionary, f: int) -> String:
	if not CState.is_human(st, f):
		return "only a player can leave a team"
	if CState.team_members(st, CState.team(st, f)).size() < 2:
		return "not on a team"
	if leaving_since(st, f) >= 0:
		return "already leaving"
	var l: Array = (st["leaving"] as Array).duplicate() if st.has("leaving") else []
	l.append([f, int(st["turn"])])
	l.sort_custom(func(a, b): return int(a[0]) < int(b[0]))
	st["leaving"] = l
	event(st, {"k": "team_notice", "f": f, "team": CState.team(st, f), "turns": TEAM_NOTICE_TURNS})
	return ""


## End of a turn: leavers whose notice has run out get a team of their own
## and peace with their old mates.
static func process_leaving(st: Dictionary) -> void:
	if not st.has("leaving"):
		return
	var keep: Array = []
	var gone: Array = []
	for e in st["leaving"]:
		if int(st["turn"]) - int(e[1]) >= TEAM_NOTICE_TURNS:
			gone.append(int(e[0]))
		else:
			keep.append(e)
	_set_leaving(st, keep)
	for f in gone:
		var old := CState.team(st, f)
		var mates := CState.team_members(st, old)
		mates.erase(f)
		if mates.is_empty():
			continue
		var fresh := 0
		for t in st["teams"]:
			fresh = maxi(fresh, int(t) + 1)
		st["teams"][f] = fresh
		for m in mates:
			CState.set_dip(st, f, int(m), CState.PEACE)
		event(st, {"k": "team_left", "f": f, "team": old, "mates": mates.duplicate()})


## Post a proposal for human g to answer next turn (once per from / to /
## what a turn).
static func post_proposal(st: Dictionary, f: int, g: int, what: String) -> void:
	for p in st["proposals"]:
		if int(p["from"]) == f and int(p["to"]) == g and str(p["what"]) == what:
			return
	var id := int(st["next_proposal"])
	st["next_proposal"] = id + 1
	(st["proposals"] as Array).append({"id": id, "from": f, "to": g, "what": what, "turn": int(st["turn"])})
	event(st, {"k": "proposal", "from": f, "to": g, "what": what, "id": id})


# ---------------------------------------------- gifts between players ---
# The human players may hand each other a city (with its garrison,
# buildings, level and any construction; never while an army of the giver
# stands in it, or it is besieged, a battle is pending there or recruits are
# queued there) and money. A free city gift and a money gift take effect when
# the turn is resolved. A city for a price is a proposal in the state's
# "proposals" list, {id, from, to, what = kind, kind ("offer_city": `from`
# owns r and asks `price` of `to`; "ask_city": `from` offers `price` for
# `to`'s city r), r, price, turn}; `to` answers it the next turn
# (accept_offer / decline_offer); on acceptance every check runs again and
# the city and the money move together, else the deal is refused with an
# event saying why. Like the AI's proposals it lapses after that turn. The
# AI never makes, sees or answers these entries.

## "" if f and g are both alive human players (allied).
static func gift_partner_check(st: Dictionary, f: int, g: int) -> String:
	if g < 0 or g >= CState.nf() or g == f or not CState.alive(st, g) or not CState.alive(st, f):
		return "no such faction"
	if not (CState.is_human(st, f) and CState.is_human(st, g) and CState.friendly(st, f, g)):
		return "only between allied players"
	return ""


## True if an army of faction f stands in settlement r (version 6: on its
## site cell; older formats: in the region).
static func army_in_city(st: Dictionary, f: int, r: int) -> bool:
	var grid := CState.grid_on(st)
	for a in st["armies"]:
		if int(a["f"]) != f:
			continue
		if (grid and CState.cell(a) == CGrid.site(r)) or (not grid and int(a["r"]) == r):
			return true
	return false


## "" if city r may pass from `giver` to `payer` for `price` now.
static func city_deal_check(st: Dictionary, giver: int, payer: int, r: int, price: int) -> String:
	var why := gift_partner_check(st, giver, payer)
	if why != "":
		return why
	if r < 0 or r >= CData.region_count():
		return "bad order"
	if CState.owner(st, r) != giver:
		return "not the giver's city"
	if price < 0:
		return "bad price"
	if CState.regions_of(st, giver).size() <= 1:
		return "the giver's last city"
	if not CState.siege_at(st, r).is_empty():
		return "besieged"
	if not CState.battle_at(st, r).is_empty():
		return "battle pending here"
	if not (st["regions"][r]["queue"] as Array).is_empty():
		return "recruits queued there"
	if army_in_city(st, giver, r):
		return "an army of the giver stands in the city"
	if price > int(st["factions"][payer]["treasury"]):
		return "%s cannot pay %d" % [CData.faction_name(payer), price]
	return ""


## A city proposal about r made this turn (one per city per turn).
static func _city_offer_now(st: Dictionary, r: int) -> bool:
	for p in st["proposals"]:
		if p.has("kind") and int(p["r"]) == r and int(p["turn"]) == int(st["turn"]):
			return true
	return false


## "" if faction f may give its city r to the allied player `to` (price 0)
## or offer it for `price`.
static func gift_region_check(st: Dictionary, f: int, r: int, to: int, price: int) -> String:
	var why := city_deal_check(st, f, to, r, price)
	if why == "" and price > 0 and _city_offer_now(st, r):
		return "already offered this turn"
	return why


## "" if faction f may offer `price` (> 0) for the allied player's city r.
static func buy_region_check(st: Dictionary, f: int, r: int, price: int) -> String:
	if r < 0 or r >= CData.region_count():
		return "bad order"
	if price <= 0:
		return "name a price"
	var why := city_deal_check(st, CState.owner(st, r), f, r, price)
	if why == "" and _city_offer_now(st, r):
		return "already offered this turn"
	return why


## "" if faction f may give `amount` (> 0) to the allied player `to`.
static func gift_money_check(st: Dictionary, f: int, to: int, amount: int) -> String:
	var why := gift_partner_check(st, f, to)
	if why != "":
		return why
	if amount <= 0:
		return "name an amount"
	if amount > int(st["factions"][f]["treasury"]):
		return "not enough money"
	return ""


static func _gift_region(st: Dictionary, f: int, r: int, to: int, price: int) -> String:
	var why := gift_region_check(st, f, r, to, price)
	if why != "":
		return why
	if price == 0:
		_transfer_city(st, f, to, r, 0)
	else:
		_city_proposal(st, f, to, r, price, "offer_city")
	return ""


static func _buy_region(st: Dictionary, f: int, r: int, price: int) -> String:
	var why := buy_region_check(st, f, r, price)
	if why != "":
		return why
	_city_proposal(st, f, CState.owner(st, r), r, price, "ask_city")
	return ""


static func _gift_money(st: Dictionary, f: int, to: int, amount: int) -> String:
	var why := gift_money_check(st, f, to, amount)
	if why != "":
		return why
	st["factions"][f]["treasury"] = int(st["factions"][f]["treasury"]) - amount
	st["factions"][to]["treasury"] = int(st["factions"][to]["treasury"]) + amount
	event(st, {"k": "gift_money", "f": f, "to": to, "amount": amount})
	return ""


static func _city_proposal(st: Dictionary, f: int, g: int, r: int, price: int, kind: String) -> void:
	var id := int(st["next_proposal"])
	st["next_proposal"] = id + 1
	(st["proposals"] as Array).append({"id": id, "from": f, "to": g, "what": kind, "kind": kind, "r": r, "price": price,
		"turn": int(st["turn"])})
	event(st, {"k": "city_offer", "from": f, "to": g, "r": r, "price": price, "kind": kind, "id": id})


## City r (with everything in it) passes from giver to payer, who pays price.
static func _transfer_city(st: Dictionary, giver: int, payer: int, r: int, price: int) -> void:
	st["factions"][payer]["treasury"] = int(st["factions"][payer]["treasury"]) - price
	st["factions"][giver]["treasury"] = int(st["factions"][giver]["treasury"]) + price
	st["regions"][r]["owner"] = payer
	event(st, {"k": "gift_region", "f": giver, "to": payer, "r": r, "price": price})


## The player's answer to a city proposal addressed to it.
static func _answer_offer(st: Dictionary, f: int, id: int, accept: bool) -> String:
	for p in st["proposals"]:
		if int(p["id"]) != id or int(p["to"]) != f or not p.has("kind"):
			continue
		var g := int(p["from"])
		var r := int(p["r"])
		var price := int(p["price"])
		var giver := g if str(p["kind"]) == "offer_city" else f
		var payer := f if giver == g else g
		st["proposals"].erase(p)
		if not accept:
			event(st, {"k": "city_declined", "f": f, "to": g, "r": r, "price": price})
			return ""
		var why := city_deal_check(st, giver, payer, r, price)
		if why != "":
			event(st, {"k": "city_refused", "f": f, "to": g, "r": r, "price": price, "why": why})
		else:
			_transfer_city(st, giver, payer, r, price)
		return ""
	return "no such offer"


# --------------------------------------------------------------- economy ---

## Income of faction f: {regions, trade, total} (per turn).
static func income(st: Dictionary, f: int) -> Dictionary:
	var reg := 0
	var markets := 0
	var owned := CState.regions_of(st, f)
	var rmap := raid_map(st) if CState.grid_on(st) else PackedInt32Array()
	for r in owned:
		reg += region_income(st, r, rmap)
		markets += CState.building(st, r, CData.MARKET)
	var raid := 0
	if CState.grid_on(st):
		# Version 6: what our raiders take from enemy regions.
		for r in CData.region_count():
			if rmap[r] == f:
				raid += _base_income(st, r) * CData.RAID_PCT / 100
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
	var out := {"regions": reg, "trade": trade, "corruption": cut, "total": gross - cut}
	if CState.grid_on(st):
		out["raid"] = raid
		out["total"] = gross - cut + raid
	return out


static func region_income(st: Dictionary, r: int, rmap: PackedInt32Array = PackedInt32Array()) -> int:
	if not CState.siege_at(st, r).is_empty():
		return 0  # besieged: nothing comes in
	var inc := _base_income(st, r)
	if CState.grid_on(st):
		if (rmap[r] if rmap.size() > r else _raider6(st, r)) >= 0:
			inc -= inc * CData.RAID_PCT / 100  # version 6: the raiders take their share
		return inc
	if raider(st, r) >= 0:
		inc /= 2  # raided (version 5): half the income
	return inc


static func _base_income(st: Dictionary, r: int) -> int:
	var rs: Dictionary = st["regions"][r]
	return int(CData.REGIONS[r]["wealth"]) * CData.WEALTH_INCOME + int(CData.LEVEL_INCOME[int(rs["level"])]) \
		+ CState.building(st, r, CData.FARM) * CData.FARM_INCOME + CState.building(st, r, CData.MARKET) * CData.MARKET_INCOME


## Version 5: the faction raiding region r (its army stands there, at war
## with the owner, without a siege; the lowest army id), else -1.
static func raider(st: Dictionary, r: int) -> int:
	if CState.grid_on(st):
		return _raider6(st, r)
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
	var fresh := {}  # version 6: ids of the armies raised by this turn's recruits
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
			if rs.has("qa"):
				_place_recruits6(st, o, r, fresh)
			else:
				for key in q:
					_add_recruit(st, o, r, str(key))
			event(st, {"k": "recruited", "r": r, "f": o, "units": q.duplicate()})
			rs["queue"] = []
		rs.erase("qa")
	CChars.appear(st)
	CChars.pay_ransom(st)
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
	CChars.sweep(st)
	if CState.grid_on(st):
		_auto_merge6(st, fresh)
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
			a["mp"] = CState.full_mp(st, a)
		a["moved"] = 0
		a["from"] = -1
	# Proposals last one turn.
	var keep_p: Array = []
	for p in st["proposals"]:
		if int(p["turn"]) >= int(st["turn"]):
			keep_p.append(p)
	st["proposals"] = keep_p


## Version 6, end of turn: armies of one faction standing idle on the same
## settlement cell (not in a battle, no march stored, the same stance)
## merge, the lowest id taking in the others in id order while they fit in
## CData.ARMY_MAX; one that does not fit starts the next group. Armies
## raised by this turn's recruits (`fresh`: id -> 1) stay apart this turn
## (a "Raise new army" is not swallowed by the army in the city at once).
static func _auto_merge6(st: Dictionary, fresh: Dictionary = {}) -> void:
	var arr: Array = st["armies"]
	var gone := PackedByteArray()
	gone.resize(arr.size())
	gone.fill(0)
	var any := false
	for i in arr.size():
		var a: Dictionary = arr[i]
		if gone[i] != 0 or not _idle_in_town(a) or fresh.has(int(a["id"])):
			continue
		for j in range(i + 1, arr.size()):
			var b: Dictionary = arr[j]
			if gone[j] != 0 or int(b["f"]) != int(a["f"]) or CState.cell(b) != CState.cell(a) \
					or CState.stance(b) != CState.stance(a) or not _idle_in_town(b) or fresh.has(int(b["id"])):
				continue
			if CState.unit_count(a) + CState.unit_count(b) > CData.ARMY_MAX \
					or CChars.merge_conflict(st, int(a["id"]), int(b["id"])):
				continue
			CChars.transfer(st, int(b["id"]), int(a["id"]))
			(a["units"] as Array).append_array(b["units"])
			_one_general(a)
			a["idle"] = mini(int(a.get("idle", 0)), int(b.get("idle", 0)))
			gone[j] = 1
			any = true
	if not any:
		return
	var keep: Array = []
	for i in arr.size():
		if gone[i] == 0:
			keep.append(arr[i])
	st["armies"] = keep


static func _idle_in_town(a: Dictionary) -> bool:
	return int(a["busy"]) == 0 and int(a.get("dest_x", -1)) < 0 and int(a.get("tgt", -1)) < 0 \
			and not a.has("dest_army") and CGrid.site_region(CState.cell(a)) >= 0


## New recruit: joins the faction's first army in the region with room, or
## forms a new army. Version 6: the first army of the faction (by id) on
## the settlement's cell or next to it, not in a battle, with room, else a
## new army inside the walls; so a city's recruits collect in one army
## (the next turn's recruits join it while it stays; _auto_merge6 gathers
## any others standing idle there).
static func _add_recruit(st: Dictionary, f: int, r: int, key: String) -> void:
	var unit := new_unit(st, f, r, key)
	var grid := CState.grid_on(st)
	var gen := CState.is_general(key)
	for a in st["armies"]:
		var here := CGrid.cheb(CState.cell(a), CGrid.site(r)) <= 1 if grid else int(a["r"]) == r
		if int(a["f"]) == f and here and int(a["busy"]) == 0 and CState.unit_count(a) < CData.ARMY_MAX \
				and (not gen or CState.generals(a) == 0):
			(a["units"] as Array).append(unit)
			return
	_raise_army(st, f, r, unit)


## A new army of faction f holding `unit`, in region r (version 6: inside
## the walls, on the settlement's cell). Returns its id.
static func _raise_army(st: Dictionary, f: int, r: int, unit: Dictionary) -> int:
	var id := new_army_id(st, f)
	st["factions"][f]["next_army"] = int(st["factions"][f]["next_army"]) + 1
	var na := {"id": id, "f": f, "r": r, "units": [unit], "from": -1, "moved": 0, "busy": 0}
	if CState.grid_on(st):
		CState.place(na, CGrid.site(r))  # version 6: raised inside the walls
	_insert_army(st, na)
	return id


## Version 6, end of turn: region r's recruits (queue and qa, in index
## order) join the army each was queued for while it is still ours, on or
## next to the settlement, not in a battle, with room; the entries of a
## "new" order (QA_RAISE) all join one army raised inside the walls, which
## goes into `fresh` (kept out of this turn's _auto_merge6); the others
## (QA_ANY: an old-form order that found no army, or a recruit whose army
## can no longer take it) are placed as _add_recruit does.
static func _place_recruits6(st: Dictionary, f: int, r: int, fresh: Dictionary) -> void:
	var rs: Dictionary = st["regions"][r]
	var raised := -1
	for e in queue_of(st, r):
		var key := str(e[0])
		var into := int(e[1])
		var unit := new_unit(st, f, r, key)
		if into != QA_RAISE:
			var a := CState.army(st, into) if into >= 0 else {}
			if not a.is_empty() and int(a["f"]) == f and int(a["busy"]) == 0 \
					and CGrid.cheb(CState.cell(a), CGrid.site(r)) <= 1 and CState.unit_count(a) < CData.ARMY_MAX \
					and not (CState.is_general(key) and CState.generals(a) > 0):
				(a["units"] as Array).append(unit)
			else:
				_add_recruit(st, f, r, key)
			continue
		var ra := CState.army(st, raised) if raised >= 0 else {}
		if raised >= 0 and not ra.is_empty() and CState.unit_count(ra) < CData.ARMY_MAX \
				and not (CState.is_general(key) and CState.generals(ra) > 0):
			(ra["units"] as Array).append(unit)
			continue
		raised = _raise_army(st, f, r, unit)
		fresh[raised] = 1
	rs.erase("qa")


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
## With `team` >= 0: that team's members together instead of the players.
static func victory_progress(st: Dictionary, team: int = -1) -> Dictionary:
	var regions := 0
	var caps := 0
	for r in CData.region_count():
		var ow := CState.owner(st, r)
		if (CState.is_human(st, ow) if team < 0 else (ow >= 0 and CState.team(st, ow) == team)):
			regions += 1
			if CData.KEY_CITIES.has(str(CData.REGIONS[r]["key"])):
				caps += 1
	return {"regions": regions, "capitals": caps,
		"need_regions": int(st["settings"]["victory_regions"]),
		"need_capitals": int(st["settings"]["victory_capitals"])}


static func check_victory(st: Dictionary) -> void:
	if int(st["winner"]) >= 0 or (st["humans"] as Array).is_empty():
		return
	if not _players_one_team(st):
		_check_victory_teams(st)
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


## True if the players are exactly one team (the format 6 shape: the old
## victory rule, any player's fall loses).
static func _players_one_team(st: Dictionary) -> bool:
	var hs: Array = st["humans"]
	var t := CState.team(st, int(hs[0]))
	return CState.team_members(st, t) == hs


## Victory with teams: a team wins when its members together hold the
## regions and the key cities the settings ask. winner stays 1 (a team with
## a player won) / 0 (players lost) for old readers; winner_team is the
## winning team's id. Players lose when none of their teams has a member
## left alive.
static func _check_victory_teams(st: Dictionary) -> void:
	var left := false
	for h in st["humans"]:
		for m in CState.team_members(st, CState.team(st, int(h))):
			if CState.alive(st, m):
				left = true
	if not left:
		st["winner"] = 0
		st["phase"] = "over"
		event(st, {"k": "defeat", "f": int((st["humans"] as Array)[0])})
		return
	var seen: Array = []
	for f in CState.nf():
		var t := CState.team(st, f)
		if seen.has(t):
			continue
		seen.append(t)
		var p := victory_progress(st, t)
		if int(p["regions"]) >= int(p["need_regions"]) and int(p["capitals"]) >= int(p["need_capitals"]):
			var players := false
			for m in CState.team_members(st, t):
				if CState.is_human(st, m):
					players = true
			st["winner"] = 1 if players else 0
			st["winner_team"] = t
			st["phase"] = "over"
			event(st, {"k": "victory" if players else "defeat", "team": t, "f": f})
			return


## The chronicle (optional state key, absent in older saves): the world-level
## events of the last CHRONICLE_TURNS turns, appended as they happen (so a
## battle applied later is in too). Private rows (built, recruited, failed
## orders ...) stay in `events` only.
const CHRONICLE_KINDS := ["battle", "captured", "destroyed", "eliminated", "war", "peace", "trade", "trade_end",
	"siege", "siege_lifted", "starving", "victory", "defeat", "team_joined", "team_notice", "team_left",
	"char_captured", "char_wounded", "ransom"]
const CHRONICLE_TURNS := 60


static func event(st: Dictionary, e: Dictionary) -> void:
	e["turn"] = int(st["turn"])
	(st["events"] as Array).append(e)
	if CHRONICLE_KINDS.has(str(e.get("k", ""))):
		if not st.has("chronicle"):
			st["chronicle"] = []
		var ch: Array = st["chronicle"]
		ch.append(e.duplicate(true))
		var cut := 0
		while cut < ch.size() and int(ch[cut]["turn"]) <= int(st["turn"]) - CHRONICLE_TURNS:
			cut += 1
		if cut > 0:
			st["chronicle"] = ch.slice(cut)


# ------------------------------------------ the continuous overworld (v6) ---
# State version 6 (CState.grid_on): armies stand on cells of the static nav
# grid (campaign/cgrid.gd) and walk 8-connected paths (CGrid.find_path) to a
# destination cell, an enemy army (tgt) or a hostile settlement (they stop on
# its ring, the 8 cells round it, and lay siege or storm it: the move's
# mode). Paths avoid cells a faction may not enter (lands at peace, hostile
# settlement cells, pending battles of earlier turns and their ring, sieges
# by a third party) and the zones of control of enemy armies (a circle of
# CData.ZOC cells, + 1 fortified, none on a forced march or inside walls)
# except the target's. A phase's moves run in rounds: every moving army takes
# one step a round, by army id. A step next to an enemy army (its ring) is
# contact: a field battle on that army's cell, the mover attacking (a forced
# march cannot attack: it stops). A step into an enemy's zone from outside
# stops the army before it unless that army is its target. One battle per
# region: contact where a battle started this turn joins it (or stops). An
# army on its own side's settlement cell is inside the walls; armies on the
# ring of a besieged settlement besiege it. Support: armies within
# CData.SUPPORT cells of a battle (+2 fortified) join it from their bearing.

const CGrid := preload("res://campaign/cgrid.gd")


## Zone of control radius of army a (0: none: on a forced march, in a
## battle, or inside its settlement's walls).
static func zone_r(st: Dictionary, a: Dictionary) -> int:
	if int(a["busy"]) != 0 or inside(st, a):
		return 0
	match CState.stance(a):
		CData.ST_FORCED:
			return 0
		CData.ST_FORTIFY:
			return CData.ZOC + 1
	return CData.ZOC


## The region whose siege army a takes part in as a besieger (on its
## settlement's ring), -1 none.
static func siege_of(st: Dictionary, a: Dictionary) -> int:
	if not CState.sieges_on(st) or a.is_empty():
		return -1
	var c := CState.cell(a)
	for sg in st["sieges"]:
		var r := int(sg["r"])
		var s := CGrid.site(r)
		if c != s and CGrid.cheb(c, s) <= 1 and CState.friendly(st, int(a["f"]), int(sg["f"])) \
				and CState.at_war(st, int(a["f"]), CState.owner(st, r)):
			return r
	return -1


## Army a stands inside the walls: on the cell of a settlement of its side.
static func inside(st: Dictionary, a: Dictionary) -> bool:
	var c := CState.cell(a)
	var r := CGrid.site_region(c)
	return r >= 0 and CState.friendly(st, int(a["f"]), CState.owner(st, r))


## Armies of the owner's side inside settlement r (by id).
static func inside_of(st: Dictionary, r: int) -> Array:
	var out: Array = []
	var s := CGrid.site(r)
	var o := CState.owner(st, r)
	for a in st["armies"]:
		if CState.cell(a) == s and CState.friendly(st, int(a["f"]), o):
			out.append(a)
	return out


## Armies of faction f (all of its side: allies too when side) on the ring
## of settlement r (next to its cell), by id.
static func on_ring(st: Dictionary, r: int, f: int, side: bool = false) -> Array:
	var out: Array = []
	var s := CGrid.site(r)
	for a in st["armies"]:
		var c := CState.cell(a)
		if c != s and CGrid.cheb(c, s) <= 1 and (int(a["f"]) == f or (side and CState.friendly(st, int(a["f"]), f))):
			out.append(a)
	return out


## Cells faction f may not enter this phase (1): lands of factions at peace
## with it, hostile settlement cells (a path stops on the ring), the cell
## and ring of a battle pending from an earlier turn, the ring of a
## settlement besieged by a third party.
static func block_mask(st: Dictionary, f: int) -> PackedByteArray:
	var n := CGrid.count()
	var m := PackedByteArray()
	m.resize(n)
	m.fill(0)
	for r in CData.region_count():
		var o := CState.owner(st, r)
		if not CState.friendly(st, f, o) and not CState.at_war(st, f, o):
			for c in CGrid.cells_of(r):
				m[c] = 1
			continue
		var s := CGrid.site(r)
		if not CState.friendly(st, f, o):
			m[s] = 1
		var sg := CState.siege_at(st, r)
		if not sg.is_empty() and not CState.friendly(st, f, int(sg["f"])) and not CState.friendly(st, f, o):
			for c in CGrid.disc(s, 1):
				m[c] = 1
	for b in st["battles"]:
		if int(b.get("new", 0)) == 0 and b.has("x"):
			for c in CGrid.disc(CGrid.at(int(b["x"]), int(b["y"])), 1):
				m[c] = 1
	return m


## Enemy armies of faction f that project a zone (at war, zone_r > 0), by id.
static func zone_armies(st: Dictionary, f: int) -> Array:
	var out: Array = []
	for e in st["armies"]:
		if CState.at_war(st, f, int(e["f"])) and zone_r(st, e) > 0:
			out.append(e)
	return out


## Zones of control of the enemies of f, as a per-cell count of the zones
## covering it, without the zones of the armies in `except` (ids).
static func zone_mask(st: Dictionary, f: int, except: Array = []) -> PackedInt32Array:
	var n := CGrid.count()
	var m := PackedInt32Array()
	m.resize(n)
	m.fill(0)
	for e in zone_armies(st, f):
		if except.has(int(e["id"])):
			continue
		for c in CGrid.disc(CState.cell(e), zone_r(st, e)):
			m[c] += 1
	return m


## What a move of army a to cell `dest` (or after enemy army tgt) aims at:
## {cell (where the search goes), adjacent (stop next to it), tgt (army id
## or -1), r (a hostile settlement it besieges or storms, -1), targets
## (enemy army ids whose zones it may enter), kind ("move", "inside" (into
## our own settlement), "siege", "assault", "attack", "relief", "sally",
## "join" (our siege), "merge" (join: another army of ours to merge into;
## then "join" holds its id)}.
static func move_aim(st: Dictionary, a: Dictionary, dest: int, tgt: int = -1, mode: int = CData.MODE_SIEGE,
		join: int = -1) -> Dictionary:
	var f := int(a["f"])
	var out := {"cell": dest, "adjacent": 0, "tgt": -1, "r": -1, "targets": [], "kind": "move"}
	if join >= 0:
		var j := CState.army(st, join)
		if not j.is_empty() and int(j["f"]) == f and join != int(a["id"]):
			out["cell"] = CState.cell(j)
			out["adjacent"] = 1
			out["kind"] = "merge"
			out["join"] = join
			return out
	if tgt >= 0:
		var t := CState.army(st, tgt)
		if not t.is_empty() and CState.at_war(st, f, int(t["f"])):
			var tc := CState.cell(t)
			var t_reg := CGrid.site_region(tc)
			if t_reg >= 0 and inside(st, t):
				dest = tc  # inside its walls: that is the settlement
			else:
				out["cell"] = tc
				out["adjacent"] = 1
				out["tgt"] = tgt
				# Its side's armies standing with it are fought too: their
				# zones may be entered.
				var tl: Array = [tgt]
				for e in st["armies"]:
					if int(e["id"]) != tgt and CState.friendly(st, int(e["f"]), int(t["f"])) and zone_r(st, e) > 0 \
							and CGrid.cheb(CState.cell(e), tc) <= CData.ZOC:
						tl.append(int(e["id"]))
				out["targets"] = tl
				var tsr := siege_of(st, t)
				if tsr >= 0:
					out["kind"] = "sally" if siege_role(st, a) == 2 else ("relief" if CState.friendly(st, f, CState.owner(st, tsr)) else "attack")
				else:
					out["kind"] = "attack"
				return out
	var r := CGrid.site_region(dest)
	if r >= 0:
		var o := CState.owner(st, r)
		if CState.friendly(st, f, o):
			out["kind"] = "inside"
			if not CState.siege_at(st, r).is_empty() and siege_role(st, a) != 2:
				out["kind"] = "relief"
				out["adjacent"] = 1
				for e in besiegers(st, r):
					out["targets"].append(int(e["id"]))
			return out
		if CState.at_war(st, f, o):
			out["adjacent"] = 1
			out["r"] = r
			var sg2 := CState.siege_at(st, r)
			if not sg2.is_empty() and CState.friendly(st, f, int(sg2["f"])):
				out["kind"] = "assault" if mode == CData.MODE_ASSAULT else "join"
			else:
				out["kind"] = "assault" if mode == CData.MODE_ASSAULT else "siege"
			# The owner's side's armies in the field near the city must be
			# beaten first: their zones may be entered.
			for e in st["armies"]:
				if CState.friendly(st, int(e["f"]), o) and o >= 0 and zone_r(st, e) > 0 \
						and CGrid.cheb(CState.cell(e), dest) <= CData.ZOC + 2:
					out["targets"].append(int(e["id"]))
	return out


## The cell of a move order (version 6): {"x", "y"} or "tgt" (an enemy
## army: its cell) or, from older clients and tests, "to" (a region: its
## settlement's cell; with mode MODE_MARCH into hostile land its camp).
static func order_cell(st: Dictionary, a: Dictionary, o: Dictionary) -> int:
	var join := int(o.get("join", -1))
	if join >= 0:
		var j := CState.army(st, join)
		return CState.cell(j) if not j.is_empty() else -1
	var tgt := int(o.get("tgt", -1))
	if tgt >= 0:
		var t := CState.army(st, tgt)
		return CState.cell(t) if not t.is_empty() else -1
	if o.has("x"):
		return CGrid.at(int(o["x"]), int(o.get("y", -1)))
	var to := int(o.get("to", -1))
	if to < 0 or to >= CData.region_count():
		return -1
	if int(o.get("mode", CData.MODE_SIEGE)) == CData.MODE_MARCH and not CState.friendly(st, int(a["f"]), CState.owner(st, to)):
		return CGrid.camp(to)
	return CGrid.site(to)


## The path army a would walk now to `dest` / tgt (or to merge into army
## join): {path, t, m (CGrid find_path), aim (move_aim)} or {"why"}. cache:
## per-phase masks by faction ("b<f>" block_mask, "z<f>" zone_mask), filled
## on demand.
static func plan_path(st: Dictionary, a: Dictionary, dest: int, tgt: int = -1, mode: int = CData.MODE_SIEGE,
		cache: Dictionary = {}, max_turns: int = 12, join: int = -1) -> Dictionary:
	if dest < 0 or not CGrid.passable(dest):
		return {"why": "no route"}
	var aim := move_aim(st, a, dest, tgt, mode, join)
	var f := int(a["f"])
	var kb := "b%d" % f
	var kz := "z%d" % f
	if not cache.has(kb):
		cache[kb] = block_mask(st, f)
		cache[kz] = zone_mask(st, f)
	var m: PackedByteArray = cache[kb]
	var zm: PackedInt32Array = cache[kz]
	var targets: Array = aim["targets"]
	if not targets.is_empty():
		zm = zm.duplicate()
		for id in targets:
			var e := CState.army(st, int(id))
			if e.is_empty() or zone_r(st, e) <= 0 or not CState.at_war(st, f, int(e["f"])):
				continue
			for c in CGrid.disc(CState.cell(e), zone_r(st, e)):
				zm[c] -= 1
	var goal := int(aim["cell"])
	var adjacent := int(aim["adjacent"]) != 0
	if not adjacent and (m[goal] != 0 or zm[goal] > 0):
		return {"why": "in an enemy's zone of control" if zm[goal] > 0 and m[goal] == 0 else "no route"}
	var full := CState.full_mp(st, a)
	if full <= 0:
		return {"why": "fortified"}
	var res := CGrid.find_path(CState.cell(a), goal, full, CState.mp(a), m, zm, adjacent, max_turns,
		400 * max_turns if max_turns <= 2 else 1500 + 1500 * mini(max_turns, 6))
	if res.is_empty():
		return {"why": "no route"}
	res["aim"] = aim
	return res


## "" if army a may march to army join and merge into it: another army of
## its faction, the two within CData.ARMY_MAX units ("too many units to
## merge").
static func join_check(st: Dictionary, a: Dictionary, join: int) -> String:
	var j := CState.army(st, join)
	if j.is_empty() or join == int(a["id"]) or int(j["f"]) != int(a["f"]):
		return "no such army"
	if CState.unit_count(a) + CState.unit_count(j) > CData.ARMY_MAX:
		return "too many units to merge"
	if CChars.merge_conflict(st, int(a["id"]), join):
		return "both armies have a hero, assassin or diplomat of the same kind"
	return ""


## "" if army a may be ordered to march to cell dest (or after enemy army
## tgt, or to merge into army join) this turn (version 6).
static func _can_move6(st: Dictionary, a: Dictionary, dest: int, tgt: int = -1, mode: int = CData.MODE_SIEGE,
		need_path: bool = true, join: int = -1) -> String:
	if a.is_empty():
		return "no such army"
	if int(a["busy"]) != 0:
		return "in a battle"
	if int(a["moved"]) != 0:
		return "already moved"
	if join >= 0:
		var why_j := join_check(st, a, join)
		if why_j != "":
			return why_j
		var j := CState.army(st, join)
		if CGrid.cheb(CState.cell(a), CState.cell(j)) <= 1:
			return together(st, a, j)  # merges at once, no march
		if siege_role(st, a) == 2:
			return "besieged"
		dest = CState.cell(j)
		tgt = -1
	if CState.stance(a) == CData.ST_FORTIFY:
		return "fortified"
	if dest < 0 or not CGrid.passable(dest):
		return "no route"
	if siege_role(st, a) == 2:
		# Inside a besieged settlement: only a sally against a besieger.
		var t := CState.army(st, tgt)
		if t.is_empty() or siege_of(st, t) != int(a["r"]):
			return "besieged"
		return ""
	if dest == CState.cell(a) and tgt < 0:
		var r := CGrid.site_region(dest)
		if r < 0 or CState.friendly(st, int(a["f"]), CState.owner(st, r)):
			return "already there"
	var why := can_enter(st, int(a["f"]), CGrid.region(dest))
	if why != "" and tgt < 0:
		return why
	if CState.stance(a) == CData.ST_FORCED:
		var aim := move_aim(st, a, dest, tgt, mode, join)
		if str(aim["kind"]) not in ["move", "inside", "merge"]:
			return "on a forced march: cannot attack"
	if not need_path:
		return ""
	var pp := plan_path(st, a, dest, tgt, mode, {}, 12, join)
	if pp.has("why"):
		return str(pp["why"])
	return ""


## Version 6: run one phase's moves in rounds. moves: [[army id, dest cell,
## faction, mode, persist, tgt, join], ...] (dest -1 with a tgt: its cell;
## join (optional, -1): an army of the mover's faction to merge into, its
## cell is the destination and the move ends when it is gone). Paths
## are computed as the phase starts; round k moves every army one step, by
## army id; contact, zones, sieges and joining battles as described above.
static func execute_moves6(st: Dictionary, moves: Array) -> void:
	var list := moves.duplicate()
	list.sort_custom(func(x, y): return int(x[0]) < int(y[0]))
	var plans: Array = []
	var seen := {}
	var cache := {}
	_mlog = []
	for mv in list:
		var id := int(mv[0])
		if seen.has(id):
			continue
		seen[id] = 1
		var a := CState.army(st, id)
		if a.is_empty() or int(a["f"]) != int(mv[2]):
			continue
		var tgt := int(mv[5]) if (mv as Array).size() > 5 else -1
		var join := int(mv[6]) if (mv as Array).size() > 6 else -1
		var dest := int(mv[1])
		if join >= 0:
			var jt := CState.army(st, join)
			if jt.is_empty() or int(jt["f"]) != int(a["f"]):
				event(st, {"k": "move_failed", "f": int(a["f"]), "army": id, "to": -1, "why": "the army to merge into is gone"})
				_drop_march(a)
				continue
			dest = CState.cell(jt)
			tgt = -1
		if tgt >= 0:
			var t := CState.army(st, tgt)
			if t.is_empty() or not CState.at_war(st, int(a["f"]), int(t["f"])):
				tgt = -1
				if dest < 0 or not t.is_empty():
					_drop_march(a)
					continue
			else:
				dest = CState.cell(t)
		var mode := int(mv[3])
		var persist := int(mv[4]) if (mv as Array).size() > 4 else 0
		if mustering(st, id):
			# Recruits are joining it this turn: it stays; a march for later
			# turns is kept.
			event(st, {"k": "move_failed", "f": int(a["f"]), "army": id, "to": CGrid.region(dest) if dest >= 0 else -1, "why": "mustering"})
			if persist != 0 and dest >= 0:
				_store_march(a, dest, tgt, mode, join)
			else:
				_drop_march(a)
			continue
		var why := _can_move6(st, a, dest, tgt, mode, false, join)
		if why == "" and siege_role(st, a) == 2 and join < 0:
			_sally6(st, a, CState.army(st, tgt))  # inside a besieged city: a sally
			_drop_march(a)
			continue
		var aim := move_aim(st, a, dest, tgt, mode, join)
		if why == "" and int(aim["adjacent"]) != 0 and CGrid.cheb(CState.cell(a), int(aim["cell"])) <= 1:
			# Already next to what it means to act on.
			plans.append({"id": id, "path": [], "k": 0, "aim": aim, "mode": mode, "persist": persist, "stop": 0,
				"dest": dest, "tgt": tgt, "join": join})
			continue
		var pp := {}
		if why == "":
			# A march for this turn only (the AI's) looks two turns ahead.
			pp = plan_path(st, a, dest, tgt, mode, cache, 12 if persist != 0 else 2, join)
			why = str(pp.get("why", ""))
		if why != "":
			if why != "already there":
				event(st, {"k": "move_failed", "f": int(a["f"]), "army": id, "to": CGrid.region(dest), "why": why})
			_drop_march(a)
			continue
		plans.append({"id": id, "path": pp["path"], "k": 0, "aim": pp["aim"], "mode": mode, "persist": persist,
			"stop": 0, "dest": dest, "tgt": tgt, "join": join})
	# Armies already next to what they mean to act on.
	for p in plans:
		if (p["path"] as Array).is_empty():
			var a := CState.army(st, int(p["id"]))
			if not a.is_empty() and int(a["busy"]) == 0:
				_arrive6(st, a, p)
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
			var res := _step6(st, a, int(path[int(p["k"])]), p)
			if res == "" or res == "stop":
				p["k"] = int(p["k"]) + 1
				moving = true
			if res != "":
				p["stop"] = 1
			if res == "" and int(p["k"]) >= path.size():
				_arrive6(st, a, p)
	if not _mlog.is_empty():
		event(st, {"k": "moves", "steps": _mlog})
	_mlog = []
	for p in plans:
		var a := CState.army(st, int(p["id"]))
		if a.is_empty():
			continue
		var done := int(p["k"]) >= (p["path"] as Array).size() or int(a["busy"]) != 0
		if int(p.get("follow", 0)) != 0 and int(a["busy"]) == 0:
			done = false  # a merge that did not happen yet: keep following the army
		if done or int(p["persist"]) == 0:
			_drop_march(a)
		else:
			_store_march(a, int(p["dest"]), int(p["tgt"]), int(p["mode"]), int(p["join"]))


## Keep a march for the next turns (dest cell, enemy army tgt, mode, the
## army it marches to merge into).
static func _store_march(a: Dictionary, dc: int, tgt: int, mode: int, join: int) -> void:
	a["dest_x"] = CGrid.cx(dc)
	a["dest_y"] = CGrid.cy(dc)
	a["tgt"] = tgt
	a["mode"] = mode
	if join >= 0:
		a["dest_army"] = join
	else:
		a.erase("dest_army")


static func _drop_march(a: Dictionary) -> void:
	a["dest_x"] = -1
	a["dest_y"] = -1
	a["tgt"] = -1
	a.erase("dest_army")


static var _mlog: Array = []


## Record a step for the view's replay: each phase's steps become one event
## {k: "moves", steps: [[army, x, y], ...]} in the order they were taken
## (rounds, armies by id within a round).
static func _log_step(_st: Dictionary, a: Dictionary) -> void:
	_mlog.append([int(a["id"]), int(a["x"]), int(a["y"])])


## One step of army a onto cell c (a neighbour or across a sea lane).
## Returns "" (moved on), "stop" (moved and its march ends: a battle) or why
## it did not move (it stops where it is).
static func _step6(st: Dictionary, a: Dictionary, c: int, p: Dictionary) -> String:
	var f := int(a["f"])
	var c0 := CState.cell(a)
	var full := CState.full_mp(st, a)
	var left := CState.mp(a)
	var cost := CGrid.step_cost(c0, c)
	if cost <= 0:
		if left < full:
			return "out of points"
		cost = left  # a sea lane takes the whole turn
	elif left < cost:
		return "out of points"
	var rc := CGrid.region(c)
	var why := can_enter(st, f, rc)
	if why != "" and why != "battle pending there":
		return why
	var forced := CState.stance(a) == CData.ST_FORCED
	# A battle started this turn next to the cell: join it.
	for b in st["battles"]:
		if not b.has("x"):
			continue
		var bc := CGrid.at(int(b["x"]), int(b["y"]))
		if CGrid.cheb(bc, c) <= 1:
			if int(b.get("new", 0)) == 0:
				return "battle pending there"
			if forced:
				return "on a forced march"
			var jw := _join6(st, a, b, c, cost)
			return "stop" if jw == "" else jw
	# Contact: next to an enemy army in the field (the first by id); else a
	# zone of control entered from outside stops it (unless that army is
	# its target). Armies more than 3 cells away cannot matter (zones are at
	# most ZOC + 1 = 3).
	var targets: Array = p["aim"]["targets"]
	var x1 := CGrid.cx(c)
	var y1 := CGrid.cy(c)
	var aid := int(a["id"])
	var zone_hit := false
	for e in st["armies"]:
		var ex := int(e["x"])
		var ey := int(e["y"])
		if absi(ex - x1) > 3 or absi(ey - y1) > 3 or int(e["id"]) == aid or int(e["busy"]) != 0:
			continue
		if not CState.at_war(st, f, int(e["f"])) or inside(st, e):
			continue
		var ec := CGrid.at(ex, ey)
		if absi(ex - x1) <= 1 and absi(ey - y1) <= 1:
			if forced:
				return "on a forced march"
			return _contact6(st, a, e, c, cost)
		if zone_hit or targets.has(int(e["id"])):
			continue
		var zr := zone_r(st, e)
		if zr > 0 and CGrid.within(ec, c, zr) and not CGrid.within(ec, c0, zr):
			zone_hit = true
	if zone_hit:
		return "zone of control"
	_move_to(st, a, c, cost)
	return ""


## Army a moves onto cell c for `cost` points (the siege it leaves is
## lifted if it was the last besieger).
static func _move_to(st: Dictionary, a: Dictionary, c: int, cost: int) -> void:
	var old_r := int(a["r"])
	var was := siege_of(st, a)
	a["from"] = old_r
	CState.place(a, c)
	a["moved"] = 1
	a["mp"] = maxi(CState.mp(a) - cost, 0)
	_log_step(st, a)
	if was >= 0 and siege_of(st, a) != was:
		_left_siege(st, was)


## The march of plan p ended next to its aim (or already was): lay siege,
## storm, or nothing more.
static func _arrive6(st: Dictionary, a: Dictionary, p: Dictionary) -> void:
	var aim: Dictionary = p["aim"]
	if str(aim["kind"]) == "merge":
		_arrive_merge(st, a, p)
		return
	if int(a["busy"]) == 0 and CState.stance(a) != CData.ST_FORCED:
		# Next to an army it targets (the march ended there, or started there).
		for id in aim["targets"]:
			var e := CState.army(st, int(id))
			if not e.is_empty() and int(e["busy"]) == 0 and CState.at_war(st, int(a["f"]), int(e["f"])) \
					and not inside(st, e) and CGrid.cheb(CState.cell(e), CState.cell(a)) <= 1:
				_contact6(st, a, e, CState.cell(a), 0)
				return
		if str(aim["kind"]) == "relief":
			# At the walls of our besieged city with no besieger next to it:
			# the relief falls on the besiegers all the same.
			var rr := CGrid.site_region(int(aim["cell"]))
			if rr >= 0 and CGrid.cheb(CState.cell(a), CGrid.site(rr)) <= 1 and CState.battle_at(st, rr).is_empty():
				for e in besiegers(st, rr):
					if int(e["busy"]) == 0:
						_contact6(st, a, e, CState.cell(a), 0)
						return
	var r := int(aim["r"])
	if r < 0 or int(a["busy"]) != 0 or CGrid.cheb(CState.cell(a), CGrid.site(r)) > 1:
		return
	if CState.stance(a) == CData.ST_FORCED or not CState.at_war(st, int(a["f"]), CState.owner(st, r)):
		return
	var sg := CState.siege_at(st, r)
	if not sg.is_empty():
		if CState.friendly(st, int(a["f"]), int(sg["f"])):
			_set_from(sg, int(a["id"]), int(a["from"]))
			if int(p["mode"]) == CData.MODE_ASSAULT and CState.battle_at(st, r).is_empty():
				_siege_battle6(st, r, "assault", {})
		return
	if not CState.battle_at(st, r).is_empty():
		return
	if int(p["mode"]) == CData.MODE_ASSAULT:
		_assault6(st, r, a)
	else:
		start_siege(st, r, a, int(a["from"]))


## The march of plan p ended next to the army it merges into (aim "join"):
## merge now when both are free; if that army moved on or is in a battle,
## keep following it (p "follow"); too many units ends the move.
static func _arrive_merge(st: Dictionary, a: Dictionary, p: Dictionary) -> void:
	var t := CState.army(st, int(p["aim"]["join"]))
	if t.is_empty() or int(t["f"]) != int(a["f"]):
		return
	if CGrid.cheb(CState.cell(a), CState.cell(t)) > 1 or int(t["busy"]) != 0 or int(a["busy"]) != 0:
		p["follow"] = 1
		return
	var why := together(st, a, t)
	if why == "" and CState.unit_count(a) + CState.unit_count(t) > CData.ARMY_MAX:
		why = "too many units to merge"
	if why == "" and CChars.merge_conflict(st, int(a["id"]), int(t["id"])):
		why = "both armies have a hero, assassin or diplomat of the same kind"
	if why != "":
		event(st, {"k": "move_failed", "f": int(a["f"]), "army": int(a["id"]), "to": -1, "why": why})
		return
	_absorb(st, t, a)


## A settlement battle at r without a siege (storming on arrival): army a
## and the armies of its side on the ring attack; the garrison and the
## armies inside (and the owner's side on the ring) defend.
static func _assault6(st: Dictionary, r: int, a: Dictionary) -> Dictionary:
	var o := CState.owner(st, r)
	var defs: Array = []
	for d in st["armies"]:
		if int(d["busy"]) == 0 and CState.friendly(st, int(d["f"]), o) and o >= 0 \
				and CGrid.cheb(CState.cell(d), CGrid.site(r)) <= 1:
			defs.append(int(d["id"]))
			d["busy"] = 1
	var att: Array = [int(a["id"])]
	var from: Array = [[int(a["id"]), int(a["from"])]]
	var count := CState.unit_count(a)
	a["busy"] = 1
	for d in on_ring(st, r, int(a["f"]), true):
		if int(d["busy"]) != 0 or not CState.at_war(st, int(d["f"]), o) or count + CState.unit_count(d) > CData.BATTLE_SIDE_MAX:
			continue
		count += CState.unit_count(d)
		att.append(int(d["id"]))
		from.append([int(d["id"]), int(d["from"])])
		d["busy"] = 1
	var s := CGrid.site(r)
	var b := {"id": int(st["next_battle"]), "r": r, "turn": int(st["turn"]), "att": att, "def": defs,
		"att_f": int(a["f"]), "def_f": o, "reinf": [], "settlement": 1, "new": 1, "from": from,
		"x": CGrid.cx(s), "y": CGrid.cy(s), "app": CGrid.sector(s, CState.cell(a)), "edge": []}
	st["next_battle"] = int(st["next_battle"]) + 1
	(st["battles"] as Array).append(b)
	return b


## A battle of the siege of r (start_siege_battle) with its cell: the
## settlement's for an assault or a sally, the contacted besieger's for a
## relief.
static func _siege_battle6(st: Dictionary, r: int, kind: String, reliever: Dictionary, at: int = -1) -> Dictionary:
	var b := start_siege_battle(st, r, kind, reliever)
	if b.is_empty():
		return b
	var c := at if at >= 0 else CGrid.site(r)
	if not reliever.is_empty() and not (b["def"] as Array).has(int(reliever["id"])):
		(b["def"] as Array).append(int(reliever["id"]))
		reliever["busy"] = 1
	b["x"] = CGrid.cx(c)
	b["y"] = CGrid.cy(c)
	b["app"] = CGrid.sector(c, CState.cell(reliever)) if not reliever.is_empty() else -1
	b["edge"] = []
	return b


## A sally: army a inside besieged r rides out against the besiegers.
static func _sally6(st: Dictionary, a: Dictionary, t: Dictionary) -> void:
	var r := int(a["r"])
	if not CState.battle_at(st, r).is_empty() or CState.siege_at(st, r).is_empty():
		return
	_siege_battle6(st, r, "sally", {}, CState.cell(t) if not t.is_empty() else -1)


## Army a, stepping onto cell c, runs into enemy army e: a field battle on
## e's cell (a relief if e besieges a settlement of a's side), or a's side
## joins the battle already started in that region this turn.
static func _contact6(st: Dictionary, a: Dictionary, e: Dictionary, c: int, cost: int) -> String:
	var er := int(e["r"])
	# A besieger of a city of a's side: the relief is that city's battle
	# (its ring may lie in a neighbouring region).
	var sr := siege_of(st, e)
	var relief := sr >= 0 and CState.friendly(st, int(a["f"]), CState.owner(st, sr))
	if relief:
		er = sr
	var bx := CState.battle_at(st, er)
	if not bx.is_empty():
		if int(bx.get("new", 0)) == 0:
			return "battle pending there"
		var jw := _join6(st, a, bx, c, cost)
		return "stop" if jw == "" else jw
	var c0 := CState.cell(a)
	if c != c0:
		_move_to(st, a, c, cost)
	var ec := CState.cell(e)
	if relief:
		_siege_battle6(st, er, "relief", a, ec)
	else:
		var defs: Array = [e]
		for d in st["armies"]:
			if int(d["id"]) != int(e["id"]) and int(d["busy"]) == 0 and CState.friendly(st, int(d["f"]), int(e["f"])) \
					and not inside(st, d) and CGrid.cheb(CState.cell(d), ec) <= 1 and CState.at_war(st, int(a["f"]), int(d["f"])):
				defs.append(d)
		var b := start_field_battle(st, er, [a], defs)
		b["x"] = CGrid.cx(ec)
		b["y"] = CGrid.cy(ec)
		b["app"] = CGrid.sector(ec, c0)
		if not (b["from"] as Array).is_empty():
			b["from"][0][1] = int(a["from"])
	event(st, {"k": "intercepted", "r": er, "f": int(a["f"]), "by": int(e["f"]), "army": int(a["id"]),
		"x": int(e["x"]), "y": int(e["y"])})
	return "stop"


## Army a steps onto cell c next to battle b (started this turn) and joins
## it on its side (version 6 join_battle).
static func _join6(st: Dictionary, a: Dictionary, b: Dictionary, c: int, cost: int) -> String:
	var af := int(a["f"])
	var side := -1
	if CState.friendly(st, af, int(b["att_f"])) and CState.at_war(st, af, int(b["def_f"])):
		side = 0
	elif CState.friendly(st, af, int(b["def_f"])) and int(b["def_f"]) >= 0:
		side = 1
	if side < 0:
		return "battle there"
	var count := CState.unit_count(a)
	for d in battle_armies(st, b)[side]:
		count += CState.unit_count(d)
	if count > CData.BATTLE_SIDE_MAX:
		return "battle side full"
	var left := int(a["r"])
	if c != CState.cell(a):
		_move_to(st, a, c, cost)
	a["busy"] = 1
	(b["att" if side == 0 else "def"] as Array).append(int(a["id"]))
	if b.has("from"):
		(b["from"] as Array).append([int(a["id"]), left])
	var sg := CState.siege_at(st, int(b["r"]))
	if side == 0 and not sg.is_empty():
		_set_from(sg, int(a["id"]), left)
	return ""


## Version 6 support: armies of either side within CData.SUPPORT cells of
## the battle's cell (+2 fortified), in the field, not in a battle or a
## siege, not on a forced march, join it until a side has BATTLE_SIDE_MAX
## field units; each records its bearing (CGrid.sector) in b["edge"].
static func _support6(st: Dictionary, b: Dictionary, counts: Array, leads: Array) -> void:
	if not b.has("edge"):
		b["edge"] = []
	var bc := CGrid.at(int(b["x"]), int(b["y"])) if b.has("x") else CGrid.site(int(b["r"]))
	for a in st["armies"]:
		if int(a["busy"]) != 0 or siege_role(st, a) != 0 or inside(st, a) or CState.stance(a) == CData.ST_FORCED:
			continue
		var af := int(a["f"])
		var side := -1
		for s in 2:
			if side < 0 and leads[s] >= 0 and CState.friendly(st, af, leads[s]):
				side = s
		if side < 0 or counts[side] + CState.unit_count(a) > CData.BATTLE_SIDE_MAX:
			continue
		if not CGrid.within(bc, CState.cell(a), support_r(a)):
			continue
		counts[side] += CState.unit_count(a)
		(b["reinf"] as Array).append(int(a["id"]))
		(b["edge"] as Array).append([int(a["id"]), CGrid.sector(bc, CState.cell(a))])
		a["busy"] = 1


static func support_r(a: Dictionary) -> int:
	return CData.SUPPORT + (2 if CState.stance(a) == CData.ST_FORTIFY else 0)


## For the view: which armies army a could support (or be supported by:
## friendly, in the field, within either's support radius) and which enemy
## armies it can attack this turn (reach a cell next to them). {support
## [ids], attack [ids]}.
static func links_of(st: Dictionary, a: Dictionary, reach_t: PackedInt32Array = PackedInt32Array()) -> Dictionary:
	var sup: Array = []
	var att: Array = []
	var c := CState.cell(a)
	for e in st["armies"]:
		if int(e["id"]) == int(a["id"]):
			continue
		var ec := CState.cell(e)
		if CState.friendly(st, int(a["f"]), int(e["f"])):
			if not inside(st, e) and (CGrid.within(c, ec, support_r(a)) or CGrid.within(ec, c, support_r(e))):
				sup.append(int(e["id"]))
		elif CState.at_war(st, int(a["f"]), int(e["f"])) and not inside(st, e) and reach_t.size() == CGrid.count():
			for k in CGrid.disc(ec, 1):
				if reach_t[k] == 0:
					att.append(int(e["id"]))
					break
	return {"support": sup, "attack": att}


## Cells army a reaches this turn (version 6, for the view): per cell 0 this
## turn, 1 next turn, -1 not. It may enter enemy zones (and stops there).
static func reach6(st: Dictionary, a: Dictionary, turns: int = 0) -> PackedInt32Array:
	var f := int(a["f"])
	var m := block_mask(st, f)
	var zm := zone_mask(st, f)
	var full := CState.full_mp(st, a)
	if full <= 0 or int(a["busy"]) != 0 or int(a["moved"]) != 0:
		var none := PackedInt32Array()
		none.resize(CGrid.count())
		none.fill(-1)
		return none
	return CGrid.reach(CState.cell(a), full, CState.mp(a), m, turns, zm)


## Version 6 retreat of a beaten army: the best cell within 5 of where it
## stands, at least 2 from the battle's cell, that its side may enter and
## that lies in no enemy's zone (farthest from the battle; friendly land
## first; for an attacker toward where it came from); else the nearest
## friendly region's field cell if `far`; else it is destroyed.
static func _retreat6(st: Dictionary, a: Dictionary, battle_cell: int, app: int, far: bool) -> void:
	var f := int(a["f"])
	var start := CState.cell(a)
	var bc := battle_cell if battle_cell >= 0 else start
	var blk := block_mask(st, f)
	var zm := zone_mask(st, f)
	var best := -1
	var best_s := -(1 << 30)
	var seen := {start: 1}
	var q: Array[int] = [start]
	var qi := 0
	while qi < q.size():
		var u := q[qi]
		qi += 1
		for k in 8:
			var v := CGrid.at(CGrid.cx(u) + CGrid.DX[k], CGrid.cy(u) + CGrid.DY[k])
			if v < 0 or seen.has(v) or CGrid.step_cost(u, v) <= 0 or blk[v] != 0 or CGrid.cheb(v, start) > 5:
				continue
			seen[v] = 1
			q.append(v)
			if zm[v] != 0 or CGrid.cheb(v, bc) < 2 or CGrid.site_region(v) >= 0:
				continue
			var sc := CGrid.d2(v, bc) * 4
			if CState.friendly(st, f, CState.owner(st, CGrid.region(v))):
				sc += 40
			if app >= 0 and CGrid.sector(bc, v) == app:
				sc += 20
			if sc > best_s:
				best_s = sc
				best = v
	var from := int(a["r"])
	if best < 0 and far:
		var t := _nearest_friendly(st, f, from)
		if t >= 0:
			best = CState.field_cell(t)
	if best < 0:
		event(st, {"k": "destroyed", "f": f, "r": from, "army": int(a["id"]), "men": CState.men(a)})
		st["armies"].erase(a)
		return
	CState.place(a, best)
	a["moved"] = 1
	a["mp"] = 0
	_drop_march(a)
	if CState.stance(a) == CData.ST_FORTIFY:
		a["stance"] = CData.ST_DEFAULT
	event(st, {"k": "retreat", "f": f, "r": from, "to": int(a["r"]), "army": int(a["id"]), "x": int(a["x"]), "y": int(a["y"])})


## Version 6 stance order: CData.ST_* (no points spent; a fortified army
## cannot move this turn, so fortifying needs an army that has not moved).
static func _set_stance6(st: Dictionary, f: int, id: int, s: int) -> String:
	var a := CState.army(st, id)
	if a.is_empty() or int(a["f"]) != f:
		return "no such army"
	if int(a["busy"]) != 0:
		return "in a battle"
	if not CData.STANCE_NAMES.has(s):
		return "bad order"
	var cur := CState.stance(a)
	if cur == s:
		return ""
	if s == CData.ST_FORTIFY and int(a["moved"]) != 0:
		return "already moved"
	if s == CData.ST_FORCED and siege_role(st, a) == 1:
		return "besieging"
	var old_full := CState.max_mp6(a)
	a["stance"] = s
	var new_full := CState.max_mp6(a)
	var used := maxi(old_full - CState.mp(a), 0)
	a["mp"] = maxi(new_full - used, 0)
	return ""


## Version 6 raider of region r: the faction of the first army (by id) in
## the raiding stance standing in r, at war with its owner, without a siege
## there; -1 none.
static func _raider6(st: Dictionary, r: int) -> int:
	if not CState.siege_at(st, r).is_empty():
		return -1
	var o := CState.owner(st, r)
	if o < 0:
		return -1
	for a in st["armies"]:
		if int(a["r"]) == r and CState.stance(a) == CData.ST_RAID and int(a["busy"]) == 0 \
				and CState.at_war(st, int(a["f"]), o):
			return int(a["f"])
	return -1


## Version 6: the raider of every region (_raider6) in one pass.
static func raid_map(st: Dictionary) -> PackedInt32Array:
	var n := CData.region_count()
	var out := PackedInt32Array()
	out.resize(n)
	out.fill(-1)
	for a in st["armies"]:
		if CState.stance(a) != CData.ST_RAID or int(a["busy"]) != 0:
			continue
		var r := int(a["r"])
		if out[r] >= 0:
			continue
		var o := CState.owner(st, r)
		if o >= 0 and CState.at_war(st, int(a["f"]), o) and CState.siege_at(st, r).is_empty():
			out[r] = int(a["f"])
	return out


## Version 6: armies left in lands at peace go home; armies on the cell of a
## settlement no longer their side's step out next to it.
static func _check_trespass6(st: Dictionary) -> void:
	for a in (st["armies"] as Array).duplicate():
		if int(a["busy"]) != 0:
			continue
		var r := int(a["r"])
		var o := CState.owner(st, r)
		var af := int(a["f"])
		var c := CState.cell(a)
		if CGrid.site_region(c) == r and not CState.friendly(st, af, o):
			CState.place(a, CState.field_cell(r))
		if not CState.friendly(st, af, o) and not CState.at_war(st, af, o) and CState.siege_at(st, r).is_empty():
			var t := _nearest_friendly(st, af, r)
			if t < 0:
				event(st, {"k": "destroyed", "f": af, "r": r, "army": int(a["id"]), "men": CState.men(a)})
				st["armies"].erase(a)
				continue
			CState.place(a, CState.field_cell(t))
			_drop_march(a)
			event(st, {"k": "retreat", "f": af, "r": r, "to": t, "army": int(a["id"]), "x": int(a["x"]), "y": int(a["y"])})


## Version 6 move_targets: regions whose settlement army a can march to (a
## hostile one: its ring) this turn (this_turn) or within three turns.
static func _move_targets6(st: Dictionary, a: Dictionary, this_turn: bool) -> Array[int]:
	var out: Array[int] = []
	if a.is_empty() or int(a["busy"]) != 0 or int(a["moved"]) != 0 or siege_role(st, a) == 2 \
			or CState.full_mp(st, a) <= 0:
		return out
	var f := int(a["f"])
	var rt := CGrid.reach(CState.cell(a), CState.full_mp(st, a), CState.mp(a), block_mask(st, f),
		0 if this_turn else 3, zone_mask(st, f))
	for r in CData.region_count():
		if r == int(a["r"]) or can_enter(st, f, r) != "":
			continue
		var s := CGrid.site(r)
		if CState.friendly(st, f, CState.owner(st, r)):
			if rt[s] >= 0:
				out.append(r)
			continue
		for c in CGrid.disc(s, 1):
			if c != s and rt[c] >= 0:
				out.append(r)
				break
	return out
