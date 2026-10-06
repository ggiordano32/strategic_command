extends RefCounted
## Turn resolution: a pure function of (state, the players' submitted
## orders). Whichever client has the last submission runs it (milestone 4)
## and uploads the result; any client given the same inputs computes the same
## state (and state_hash).
##
## Submission (what a client sends for its faction for one turn):
##   {"turn": t, "f": faction, "base": state hash the orders were planned on
##    (informational), "orders": [order, ...]}   (orders: see crules.gd)
##
## resolve_turn(state, submissions) runs, in order:
##   1. players' war declarations and answers to AI proposals;
##   2. players' other orders (build, recruit, merge, split, disband), each
##      faction in faction order, its orders in the order given;
##   3. players' moves, all factions together, by army id; entering a hostile
##      region starts a battle (state version 4: lays siege unless the move's
##      mode is assault), entering a region whose battle started this turn
##      joins it (crules.join_battle; AI moves in step 5 too); then the
##      players' assault and sally orders (version 4), faction by faction;
##   4. players' proposals, answered by the AI at once;
##   5. AI factions act in faction order (build, recruit, move);
##   6. neighbouring armies reinforce the new battles;
##   7. battles without a player are resolved by the formula now; battles with
##      a player become pending (phase "battles") and must be resolved
##      (apply_battle) before the next turn can be planned;
##   8. AI diplomacy; end of turn (buildings, recruits, money, replenishment,
##      garrisons, growth); eliminations and victory; turn + 1.
## A faction that submitted nothing simply holds (turn timeout, later).

const CData := preload("res://campaign/cdata.gd")
const CState := preload("res://campaign/cstate.gd")
const CRules := preload("res://campaign/crules.gd")
const CBattle := preload("res://campaign/cbattle.gd")
const CAI := preload("res://campaign/cai.gd")

const KEEP_EVENTS_TURNS := 2


static func submission(st: Dictionary, f: int, orders: Array) -> Dictionary:
	return {"turn": int(st["turn"]), "f": f, "base": CState.hash_text(st), "orders": orders.duplicate(true)}


## Apply a faction's planned orders to a copy of the state (no moves, no AI,
## no end of turn), for the planning view: treasury after spending, queued
## recruits and buildings, merged and split armies. Returns {state, errors
## [[order index, reason]], moves [[army, to, mode]]}. Move, assault and
## sally orders are only validated.
static func preview(st: Dictionary, f: int, orders: Array) -> Dictionary:
	var s := CState.copy(st)
	var errors: Array = []
	var moves: Array = []
	for pass_i in 2:
		for i in orders.size():
			var o: Dictionary = orders[i]
			var t := str(o.get("t", ""))
			var first := t == "war" or t == "answer"
			if (pass_i == 0) != first:
				continue
			if t == "move":
				var why := CRules.apply_order(s, f, o)
				if why != "":
					errors.append([i, why])
				else:
					moves.append([int(o["army"]), int(o["to"]), int(o.get("mode", CData.MODE_SIEGE))])
				continue
			var why2 := CRules.apply_order(s, f, o)
			if why2 != "":
				errors.append([i, why2])
	return {"state": s, "errors": errors, "moves": moves}


static func resolve_turn(st_in: Dictionary, submissions: Array) -> Dictionary:
	var st := CState.copy(st_in)
	if str(st["phase"]) != "plan":
		push_warning("resolve_turn: phase is %s" % st["phase"])
		return st
	var turn := int(st["turn"])
	# Events: keep the last turns' for the summaries.
	var keep: Array = []
	for e in st["events"]:
		if int(e["turn"]) >= turn - KEEP_EVENTS_TURNS + 1:
			keep.append(e)
	st["events"] = keep
	var subs: Array = []
	for s in submissions:
		if int(s.get("turn", -1)) == turn and CState.is_human(st, int(s["f"])) and CState.alive(st, int(s["f"])):
			subs.append(s)
	subs.sort_custom(func(a, b): return int(a["f"]) < int(b["f"]))
	# 1-2. Declarations and answers, then the other non-move orders.
	for pass_i in 2:
		for s in subs:
			var f := int(s["f"])
			for o in s["orders"]:
				var t := str(o.get("t", ""))
				if t == "move" or t == "propose" or t == "assault" or t == "sally":
					continue
				if (t == "war" or t == "answer") != (pass_i == 0):
					continue
				var why := CRules.apply_order(st, f, o)
				if why != "":
					CRules.event(st, {"k": "order_failed", "f": f, "order": o, "why": why})
	CRules.check_sieges(st)
	# 3. Moves (mode: lay siege by default, or assault).
	var moves: Array = []
	var seen := {}
	for s in subs:
		for o in s["orders"]:
			if str(o.get("t", "")) == "move":
				var id := int(o.get("army", -1))
				if seen.has(id):
					continue
				seen[id] = 1
				moves.append([id, int(o.get("to", -1)), int(s["f"]), int(o.get("mode", CData.MODE_SIEGE))])
	moves.sort_custom(func(a, b): return a[0] < b[0])
	for m in moves:
		var a := CState.army(st, m[0])
		if a.is_empty() or int(a["f"]) != int(m[2]):
			continue
		var why := CRules.execute_move(st, a, m[1], m[3])
		if why != "":
			CRules.event(st, {"k": "move_failed", "f": int(m[2]), "army": int(m[0]), "to": int(m[1]), "why": why})
	# 3b. Assaults and sallies (version 4), faction by faction.
	for s in subs:
		var f := int(s["f"])
		for o in s["orders"]:
			var t := str(o.get("t", ""))
			if t != "assault" and t != "sally":
				continue
			var r := int(o.get("r", -1))
			var why := CRules.order_assault(st, f, r) if t == "assault" else CRules.order_sally(st, f, r)
			if why != "":
				CRules.event(st, {"k": "order_failed", "f": f, "order": o, "why": why})
	# 4. Proposals.
	for s in subs:
		var f := int(s["f"])
		for o in s["orders"]:
			if str(o.get("t", "")) != "propose":
				continue
			var g := int(o.get("to", -1))
			var what := str(o.get("what", ""))
			if CRules.check_proposal(st, f, g, what) != "" or CState.is_human(st, g):
				continue
			if CAI.accepts(st, f, g, what):
				CRules.apply_agreement(st, f, g, what)
			else:
				CRules.event(st, {"k": "refused", "from": g, "to": f, "what": what})
	CRules.check_sieges(st)
	# 5. AI factions.
	for f in CState.nf():
		CAI.act(st, f)
	CRules.check_sieges(st)
	# 6-7. Reinforcements; formula for AI-only battles.
	for b in st["battles"]:
		if int(b.get("new", 0)) != 0:
			CRules.add_reinforcements(st, b)
			b.erase("new")
	var ai_only: Array = []
	for b in st["battles"]:
		if CRules.battle_humans(st, b).is_empty():
			ai_only.append(int(b["id"]))
	for bid in ai_only:
		var b := CState.battle(st, bid)
		if not b.is_empty():
			CRules.apply_outcome(st, bid, CBattle.formula(st, b))
	# 8. Diplomacy, economy, end conditions.
	for f in CState.nf():
		CAI.diplomacy(st, f)
	CRules.end_of_turn(st)
	CRules.check_eliminations(st)
	CRules.check_victory(st)
	st["turn"] = turn + 1
	if str(st["phase"]) != "over":
		st["phase"] = "battles" if not (st["battles"] as Array).is_empty() else "plan"
	return st


## Resolve pending battle `bid` with an outcome (from the sim via
## cbattle.outcome_from_result, or the formula). Returns the new state.
static func apply_battle(st_in: Dictionary, bid: int, outcome: Dictionary) -> Dictionary:
	var st := CState.copy(st_in)
	CRules.apply_outcome(st, bid, outcome)
	return st


## Pending battles involving faction f (or any player if f < 0).
static func pending_for(st: Dictionary, f: int = -1) -> Array:
	var out: Array = []
	for b in st["battles"]:
		var hs := CRules.battle_humans(st, b)
		if (f < 0 and not hs.is_empty()) or hs.has(f):
			out.append(b)
	return out
