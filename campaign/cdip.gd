extends RefCounted
## Diplomacy beyond war, peace and trade (state format 10; docs/design/
## campaign_rules.md "Diplomacy: trust, alliances and passage"): trust (repute
## and regard, both fading; gifts), alliances (with notice, calls to arms and
## sitting out), military passage and trespass, the starting treaties and the
## treaty lines (a unit line a faction raises only while it trades with one
## of a list of factions). Every number of the plan is in the tables below,
## so a balance pass changes this file only (the AI's per-level knobs, ALLY_*,
## are in campaign/cai_profile.gd).
##
## State keys (all format 10; a state without "regard" is an older format and
## none of this runs: on()):
##   repute [n]: how faction f keeps its word, read by everyone, -50..50;
##   regard [n*n]: regard[a*n+b] how a regards b (what b did to a), -100..100;
##   gift [n*n]: the share of regard[a*n+b] that came from b's gifts (0..25);
##   passage [n*n]: passage[a*n+b] the turn until which b may cross a's land
##     (0 none; valid while turn < it);
##   fought [n*n]: battles a and b fought on one side (as allies or team
##     mates; never fades);
##   regard_log [n*n]: the last LOG_MAX [turn, delta, why] of each pair;
##   optional aleaving [[a, b, turn]]: a gave b notice of leaving their
##     alliance at turn (sorted by a, b; absent when empty);
##   optional called [[a, b, c, turn]]: a human ally b was called by a to
##     its war on c at turn and has not answered (sitting out is judged from
##     it: end_turn; sorted by a, b, c; absent when empty);
##   optional answered [[a, b, c, turn]] (2026-11-02, no format bump: absent
##     reads empty): b answered a's call to its war on c at turn and both
##     are still at war with c, allied (the gains of a call kept: towns and
##     battles won from c; dropped when a or b makes peace with c, the
##     alliance ends or one of the three is gone; sorted by a, b, c);
##   settings ai_alliances (absent = 1; 0: AI factions never propose an
##     alliance to one another).
## Events: regard {a, b, d, why; optional vs, r: a call kept (2026-11-02)},
## repute {f, d, why; optional with, vs}, alliance {a, b},
## alliance_notice {f, with, turns}, alliance_left {f, with, why}, passage {a
## grantor, b, until}, passage_end {a, b}, call {from, to, vs} (a human's
## proposal), call_answered {from, to, vs, accept, why}, call_sat_out {from,
## to, vs}, gold_gift {from, to, gold, d}, trespass {f, g, armies}; a war
## event carries "why": "called" | "trespass" when it is one.
##
## Determinism: integers, CState.rand never (nothing here is random), arrays
## in index order, no Dictionary iterated.

const CData := preload("res://campaign/cdata.gd")
const CState := preload("res://campaign/cstate.gd")
const UT := preload("res://sim/unit_types.gd")

# -------------------------------------------------------------- numbers ---
const REPUTE_MAX := 50
const REGARD_MAX := 100
# Repute (of the faction that did it).
const REP_TREATY_BREAK := -20   # war on a trade partner or an ally
const REP_UNPROVOKED := -10     # war on a faction with no army trespassing in our land (a call answered costs nothing)
const REP_SACK := -5
const REP_CALL_REFUSED := -5    # a call to arms refused or sat out
const REP_FOUGHT := 2           # a battle fought beside an ally (or a team mate)
const REP_KEPT_FAITH := 5       # (2026-11-02) a call to arms answered (the mirror of REP_CALL_REFUSED)
# Regard (of the faction it was done to, for the one that did it).
const REG_WAR := -40            # war declared on us
const REG_CITY_TAKEN := -15
const REG_SACKED := -20
const REG_TRESPASS := -2        # per army per turn
const REG_CALL_REFUSED := -20
const REG_TRADE_CANCELLED := -10
const REG_LEFT_AT_WAR := -20    # an alliance left while we are at war
const REG_PEACE := 5            # both ways
const REG_FOUGHT := 10          # both ways
const REG_TREATY := 30          # a starting treaty, both ways
# (2026-11-02) A call to arms kept: the caller's regard of the answerer
# (answering and two towns taken = 31, about the REG_TREATY a standing
# alliance carries; an alliance earns ~1 a ten turns from battles shared).
const REG_KEPT_FAITH := 15      # the call answered (war declared on the enemy)
const REG_CALL_TOWN := 8        # each settlement taken from the common enemy while the caller fights it
const REG_CALL_TOWN_OTHER := 3  # the same, every other faction at war with that enemy
const REG_CALL_BATTLE := 2      # each battle won against the common enemy
# Gifts.
const GIFT_MIN := 50            # gold
const GIFT_GOLD := 50           # gold per point of regard
const GIFT_CAP := 25            # the gift share of a regard at most
const GIFT_FADE := 2            # the gift share fades this much a turn (the rest FADE)
const FADE := 1
const LOG_MAX := 4
# The AI's answers (CAI.why): score = regard[to][from] + repute[from].
const FLOOR_TRADE := 0
const FLOOR_PASSAGE := 10
const FLOOR_ALLIANCE := 25
const FLOOR_TEAM := 50          # regard alone (and allied, and a battle fought together)
const COMMON_ENEMY := 25        # (as built) an alliance's score + this when the two are at war with one enemy
# The AI's wars (CAI.diplomacy).
const WAR_LINE := -40           # regard below this: an AI declares war on a faction trespassing in its land
const NO_WAR_REGARD := 30       # never an opportunistic war on a faction regarded this much
const HATE_REGARD := -30        # the war chance doubles on a faction regarded this low
# Treaties.
const PASSAGE_TURNS := 10
const ALLIANCE_NOTICE := 5
const CALL_WAIT := 5            # a called ally still at peace with the enemy this many turns after the call sat it out

const TREATY_LINE_WHY := "needs a trade agreement with a European nation"


static func _rules() -> GDScript:
	return load("res://campaign/crules.gd")


static func _ai() -> GDScript:
	return load("res://campaign/cai.gd")


static func _sea() -> GDScript:
	return load("res://campaign/csea.gd")


## The trust rules apply (state format 10: the arrays exist).
static func on(st: Dictionary) -> bool:
	return st.has("regard")


static func _n() -> int:
	return CState.nf()


## Add the format 10 arrays (zeros, empty logs) where missing.
static func init(st: Dictionary) -> void:
	var n := _n()
	if not st.has("repute"):
		var r: Array = []
		for i in n:
			r.append(0)
		st["repute"] = r
	for k in ["regard", "gift", "passage", "fought"]:
		if not st.has(k):
			var a: Array = []
			for i in n * n:
				a.append(0)
			st[k] = a
	if not st.has("regard_log"):
		var l: Array = []
		for i in n * n:
			l.append([])
		st["regard_log"] = l


# -------------------------------------------------------------- queries ---

static func regard(st: Dictionary, a: int, b: int) -> int:
	if not on(st) or a < 0 or b < 0 or a == b:
		return 0
	return int(st["regard"][a * _n() + b])


static func repute(st: Dictionary, f: int) -> int:
	if not on(st) or f < 0:
		return 0
	return int(st["repute"][f])


static func gift_share(st: Dictionary, a: int, b: int) -> int:
	if not on(st) or a < 0 or b < 0 or a == b:
		return 0
	return int(st["gift"][a * _n() + b])


static func fought(st: Dictionary, a: int, b: int) -> int:
	if not on(st) or a < 0 or b < 0 or a == b:
		return 0
	return int(st["fought"][a * _n() + b])


## How `to` scores an offer from `from`: regard[to][from] + repute[from].
static func score(st: Dictionary, to: int, from: int) -> int:
	return regard(st, to, from) + repute(st, from)


## The last LOG_MAX [turn, delta, why] of how a regards b.
static func regard_log(st: Dictionary, a: int, b: int) -> Array:
	if not on(st) or a < 0 or b < 0 or a == b:
		return []
	return st["regard_log"][a * _n() + b]


## a and b are allies: dip ALLIED and not on one team (team mates are
## ALLIED in the dip too, and more).
static func allied(st: Dictionary, a: int, b: int) -> bool:
	return a >= 0 and b >= 0 and a != b and CState.dip(st, a, b) == CState.ALLIED and not CState.same_team(st, a, b)


## The allies of f (not its team mates), alive, in index order.
static func allies(st: Dictionary, f: int) -> Array:
	var out: Array = []
	for g in _n():
		if CState.alive(st, g) and allied(st, f, g):
			out.append(g)
	return out


## b may cross a's land (a passage treaty in force).
static func has_passage(st: Dictionary, b: int, a: int) -> bool:
	if not on(st) or a < 0 or b < 0 or a == b:
		return false
	return int(st["passage"][a * _n() + b]) > int(st["turn"])


## Faction f may enter land of o, at peace or trade with it and not
## friendly: with passage, or (a trespass) a human army. The AI never
## trespasses (CRules.can_enter stays strict for it).
static func may_cross(st: Dictionary, f: int, o: int) -> bool:
	if not on(st) or f < 0 or o < 0 or f == o or CState.friendly(st, f, o):
		return false
	var d := CState.dip(st, f, o)
	if d != CState.PEACE and d != CState.TRADE:
		return false
	return has_passage(st, f, o) or CState.is_human(st, f)


## The turn faction f gave g notice of leaving their alliance (-1 none).
static func leaving_since(st: Dictionary, f: int, g: int) -> int:
	for e in st.get("aleaving", []):
		if int(e[0]) == f and int(e[1]) == g:
			return int(e[2])
	return -1


# ------------------------------------------------------------- changing ---

## regard[a][b] += d (clamped), logged and evented.
static func add_regard(st: Dictionary, a: int, b: int, d: int, why: String, extra: Dictionary = {}) -> void:
	if not on(st) or a < 0 or b < 0 or a == b or d == 0:
		return
	var i := a * _n() + b
	st["regard"][i] = clampi(int(st["regard"][i]) + d, -REGARD_MAX, REGARD_MAX)
	var lg: Array = st["regard_log"][i]
	lg.append([int(st["turn"]), d, why])
	while lg.size() > LOG_MAX:
		lg.remove_at(0)
	var e := {"k": "regard", "a": a, "b": b, "d": d, "why": why}
	for k in ["vs", "r", "with"]:  # (fixed key order: a Dictionary is never iterated)
		if extra.has(k):
			e[k] = int(extra[k])
	_rules().event(st, e)


static func add_repute(st: Dictionary, f: int, d: int, why: String, extra: Dictionary = {}) -> void:
	if not on(st) or f < 0 or d == 0:
		return
	st["repute"][f] = clampi(int(st["repute"][f]) + d, -REPUTE_MAX, REPUTE_MAX)
	var e := {"k": "repute", "f": f, "d": d, "why": why}
	for k in ["vs", "r", "with"]:
		if extra.has(k):
			e[k] = int(extra[k])
	_rules().event(st, e)


## The fade, once a turn (end_turn): repute and the rest of a regard step
## FADE toward 0, the gift share GIFT_FADE (so a regard of 10 that is all
## gift is 8 a turn later; one with no gift share 9). regard = gift share +
## the rest; each fades on its own; clamped after.
static func fade(st: Dictionary) -> void:
	var n := _n()
	for i in n * n:
		var g := int(st["gift"][i])
		var rest := int(st["regard"][i]) - g
		g -= mini(GIFT_FADE, g)
		rest -= signi(rest) * mini(FADE, absi(rest))
		st["gift"][i] = g
		st["regard"][i] = clampi(g + rest, -REGARD_MAX, REGARD_MAX)
	for f in n:
		var r := int(st["repute"][f])
		st["repute"][f] = r - signi(r) * mini(FADE, absi(r))


# ---------------------------------------------------------------- gifts ---

## "" if f may give g `gold` from its treasury now, else why not.
static func gift_check(st: Dictionary, f: int, g: int, gold: int) -> String:
	if not on(st):
		return "no gifts in this campaign's format"
	if g < 0 or g >= _n() or g == f or not CState.alive(st, g):
		return "no such faction"
	if CState.at_war(st, f, g):
		return "nothing to a faction at war with you"
	if gold < GIFT_MIN:
		return "a gift is %d gold or more" % GIFT_MIN
	if gold > int(st["factions"][f]["treasury"]):
		return "not enough money"
	return ""


## The "gift" order: the gold moves; regard[g][f] rises gold / GIFT_GOLD,
## its gift share capped at GIFT_CAP (the gold is paid all the same).
static func gift(st: Dictionary, f: int, g: int, gold: int) -> String:
	var why := gift_check(st, f, g, gold)
	if why != "":
		return why
	st["factions"][f]["treasury"] = int(st["factions"][f]["treasury"]) - gold
	st["factions"][g]["treasury"] = int(st["factions"][g]["treasury"]) + gold
	var i := g * _n() + f
	var d := mini(gold / GIFT_GOLD, maxi(GIFT_CAP - int(st["gift"][i]), 0))
	if d > 0:
		st["gift"][i] = int(st["gift"][i]) + d
		add_regard(st, g, f, d, "gift")
	_rules().event(st, {"k": "gold_gift", "from": f, "to": g, "gold": gold, "d": d})
	return ""


# ------------------------------------------------------- war and peace ---

## Called by CRules.declare_war after the dip is WAR (old: the dip before).
## why "called" (an ally's call answered) and "trespass" (the trespass war)
## cost no repute; any other war on a trade partner or an ally breaks a
## treaty, and on a faction with no army trespassing in f's land is
## unprovoked. The alliance is a defensive pact: every ally of g (the
## attacked) is called; f's allies are not.
static func on_war(st: Dictionary, f: int, g: int, why: String, old: int) -> void:
	if not on(st):
		return
	if why != "called" and why != "trespass":
		if old == CState.TRADE or old == CState.ALLIED:
			add_repute(st, f, REP_TREATY_BREAK, "treaty_broken")
		if not _trespassing(st, g, f):
			add_repute(st, f, REP_UNPROVOKED, "unprovoked_war")
	add_regard(st, g, f, REG_WAR, "war")
	_drop_aleaving(st, f, g)
	_call_allies(st, g, f)  # a defensive pact: only the allies of the attacked are called


## An army of f stands in a region of g.
static func _trespassing(st: Dictionary, f: int, g: int) -> bool:
	if f < 0 or g < 0:
		return false
	for a in st["armies"]:
		if int(a["f"]) == f and CState.owner(st, int(a["r"])) == g:
			return true
	return false


static func on_peace(st: Dictionary, f: int, g: int) -> void:
	add_regard(st, f, g, REG_PEACE, "peace")
	add_regard(st, g, f, REG_PEACE, "peace")
	_prune_answered(st)  # (2026-11-02) the gains of a call stop at the peace


## (2026-11-02) The callers a in index order whose call to their war on c
## faction b answered and who still fight c beside b (the "answered"
## records still live).
static func callers_vs(st: Dictionary, b: int, c: int) -> Array:
	var out: Array = []
	for e in st.get("answered", []):
		var a := int(e[0])
		if int(e[1]) == b and int(e[2]) == c and _answered_live(st, a, b, c) and not out.has(a):
			out.append(a)
	out.sort()
	return out


static func _answered_live(st: Dictionary, a: int, b: int, c: int) -> bool:
	return CState.alive(st, a) and CState.alive(st, b) and CState.alive(st, c) and allied(st, a, b) \
		and CState.at_war(st, a, c) and CState.at_war(st, b, c)


## Drop the "answered" records no longer live (array order kept).
static func _prune_answered(st: Dictionary) -> void:
	if not st.has("answered"):
		return
	var keep: Array = []
	for e in st["answered"]:
		if _answered_live(st, int(e[0]), int(e[1]), int(e[2])):
			keep.append(e)
	if keep.is_empty():
		st.erase("answered")
	else:
		st["answered"] = keep


## b kept faith with a against c (the call answered and b at war with c):
## regard[a][b] + REG_KEPT_FAITH, repute[b] + REP_KEPT_FAITH, the
## "answered" record for the gains of the war. Once per (a, b, c).
static func _kept_faith(st: Dictionary, a: int, b: int, c: int) -> void:
	if not on(st) or not CState.at_war(st, b, c):
		return
	var l: Array = (st["answered"] as Array).duplicate() if st.has("answered") else []
	for e in l:
		if int(e[0]) == a and int(e[1]) == b and int(e[2]) == c:
			return
	l.append([a, b, c, int(st["turn"])])
	l.sort_custom(func(x, y): return int(x[0]) * 10000 + int(x[1]) * 100 + int(x[2]) < int(y[0]) * 10000 + int(y[1]) * 100 + int(y[2]))
	st["answered"] = l
	add_regard(st, a, b, REG_KEPT_FAITH, "kept_faith", {"vs": c})
	add_repute(st, b, REP_KEPT_FAITH, "kept_faith", {"with": a, "vs": c})


## A city of `old` taken by f (r its region). (2026-11-02) Taken from a
## common enemy whose war f joined on a call: each caller still at war with
## `old` regards f REG_CALL_TOWN more, every other faction at war with `old`
## REG_CALL_TOWN_OTHER (index order).
static func on_capture(st: Dictionary, old: int, f: int, r: int = -1) -> void:
	if old >= 0 and f >= 0 and old != f:
		add_regard(st, old, f, REG_CITY_TAKEN, "city_taken")
		if not on(st):
			return
		var callers := callers_vs(st, f, old)
		if callers.is_empty():
			return
		for g in _n():
			if g == f or g == old or not CState.alive(st, g) or not CState.at_war(st, g, old):
				continue
			var d := REG_CALL_TOWN if callers.has(g) else REG_CALL_TOWN_OTHER
			add_regard(st, g, f, d, "took_from_enemy", {"vs": old, "r": r})


## A town of o sacked by f.
static func on_sack(st: Dictionary, o: int, f: int) -> void:
	add_repute(st, f, REP_SACK, "sack")
	if o >= 0 and o != f:
		add_regard(st, o, f, REG_SACKED, "sacked")


## A battle resolved: sides [attackers, defenders] (factions). Every pair
## on one side that is allied or on one team fought together: fought +1,
## regard +REG_FOUGHT both ways, repute +REP_FOUGHT each. (2026-11-02)
## winner (0 the attackers, 1 the defenders, -1 not known): each faction b
## on the winning side that answered a's call to its war on c, c on the
## losing side, earns regard[a][b] + REG_CALL_BATTLE (once per battle and
## caller).
static func on_battle(st: Dictionary, sides: Array, winner: int = -1) -> void:
	if not on(st):
		return
	if winner == 0 or winner == 1:
		var win: Array = (sides[winner] as Array).duplicate()
		var lose: Array = (sides[1 - winner] as Array).duplicate()
		win.sort()
		lose.sort()
		for b in win:
			var paid: Array = []
			for c in lose:
				for a in callers_vs(st, int(b), int(c)):
					if not paid.has(a):
						paid.append(a)
						add_regard(st, a, int(b), REG_CALL_BATTLE, "won_vs_enemy", {"vs": int(c)})
	var n := _n()
	for side in sides:
		var l: Array = (side as Array).duplicate()
		l.sort()
		for i in l.size():
			for j in range(i + 1, l.size()):
				var a := int(l[i])
				var b := int(l[j])
				if a < 0 or b < 0 or a == b or not (allied(st, a, b) or CState.same_team(st, a, b)):
					continue
				st["fought"][a * n + b] = int(st["fought"][a * n + b]) + 1
				st["fought"][b * n + a] = int(st["fought"][b * n + a]) + 1
				add_regard(st, a, b, REG_FOUGHT, "fought_together")
				add_regard(st, b, a, REG_FOUGHT, "fought_together")
				add_repute(st, a, REP_FOUGHT, "fought_together")
				add_repute(st, b, REP_FOUGHT, "fought_together")


## f cancelled its trade agreement with g.
static func on_cancel_trade(st: Dictionary, f: int, g: int) -> void:
	add_regard(st, g, f, REG_TRADE_CANCELLED, "trade_cancelled")


# ------------------------------------------------------------ alliances ---

## "" if f may propose an alliance to g (format 10, peace or trade, no war
## between the two sides: f and its allies against g and its allies).
static func alliance_check(st: Dictionary, f: int, g: int) -> String:
	if not on(st):
		return "no alliances in this campaign's format"
	var d := CState.dip(st, f, g)
	if d != CState.PEACE and d != CState.TRADE:
		return "make peace first"
	var sf: Array = [f] + allies(st, f)
	var sg: Array = [g] + allies(st, g)
	for x in sf:
		for y in sg:
			if CState.at_war(st, int(x), int(y)):
				return "a war between the two sides"
	return ""


static func make_alliance(st: Dictionary, f: int, g: int) -> void:
	CState.set_dip(st, f, g, CState.ALLIED)
	_rules().event(st, {"k": "alliance", "a": f, "b": g})


## The "leave_alliance" order: notice of ALLIANCE_NOTICE turns, then TRADE.
## Leaving while the ally is at war costs regard.
static func leave_alliance(st: Dictionary, f: int, g: int) -> String:
	if g < 0 or g >= _n() or g == f or not CState.alive(st, g):
		return "no such faction"
	if not allied(st, f, g):
		return "no alliance with them"
	if leaving_since(st, f, g) >= 0 or leaving_since(st, g, f) >= 0:
		return "already leaving"
	var l: Array = (st["aleaving"] as Array).duplicate() if st.has("aleaving") else []
	l.append([f, g, int(st["turn"])])
	l.sort_custom(func(x, y): return int(x[0]) < int(y[0]) or (int(x[0]) == int(y[0]) and int(x[1]) < int(y[1])))
	st["aleaving"] = l
	if _at_any_war(st, g):
		add_regard(st, g, f, REG_LEFT_AT_WAR, "left_at_war")
	_rules().event(st, {"k": "alliance_notice", "f": f, "with": g, "turns": ALLIANCE_NOTICE})
	return ""


static func _at_any_war(st: Dictionary, f: int) -> bool:
	for g in _n():
		if g != f and CState.alive(st, g) and CState.at_war(st, f, g):
			return true
	return false


## The alliance of f and g ends now (dip TRADE; why "notice" | "sat_out").
static func leave_now(st: Dictionary, f: int, g: int, why: String) -> void:
	_drop_aleaving(st, f, g)
	if not allied(st, f, g):
		return
	CState.set_dip(st, f, g, CState.TRADE)
	_rules().event(st, {"k": "alliance_left", "f": f, "with": g, "why": why})


static func _drop_aleaving(st: Dictionary, f: int, g: int) -> void:
	if not st.has("aleaving"):
		return
	var keep: Array = []
	for e in st["aleaving"]:
		if not ((int(e[0]) == f and int(e[1]) == g) or (int(e[0]) == g and int(e[1]) == f)):
			keep.append(e)
	if keep.is_empty():
		st.erase("aleaving")
	else:
		st["aleaving"] = keep


# -------------------------------------------------------- calls to arms ---

## Every ally b of a, which c attacked (not allied to c, not at war with it
## already), is called to a's defence against c: a human gets a proposal (and a "called" record for the
## sitting-out rule), an AI answers at once (CAI.why "call").
static func _call_allies(st: Dictionary, a: int, c: int) -> void:
	if a < 0 or c < 0:
		return
	for b in allies(st, a):
		if b == c or CState.at_war(st, b, c) or allied(st, b, c) or CState.same_team(st, b, c):
			continue
		if _ai().call("tutorial_shield", st, c):
			continue	# the guided first campaign: no ally joins a war on the tutorial's faction
		if CState.is_human(st, b):
			_post_call(st, a, b, c)
		else:
			var why: String = _ai().call("why", st, a, b, "call", c)
			_answered(st, a, b, c, why == "", why)


static func _post_call(st: Dictionary, a: int, b: int, c: int) -> void:
	for p in st["proposals"]:
		if str(p["what"]) == "call" and int(p["from"]) == a and int(p["to"]) == b and int(p.get("vs", -1)) == c:
			return
	var id := int(st["next_proposal"])
	st["next_proposal"] = id + 1
	(st["proposals"] as Array).append({"id": id, "from": a, "to": b, "what": "call", "vs": c, "turn": int(st["turn"])})
	_rules().event(st, {"k": "proposal", "from": a, "to": b, "what": "call", "vs": c, "id": id})
	_rules().event(st, {"k": "call", "from": a, "to": b, "vs": c})
	var l: Array = (st["called"] as Array).duplicate() if st.has("called") else []
	for e in l:
		if int(e[0]) == a and int(e[1]) == b and int(e[2]) == c:
			return
	l.append([a, b, c, int(st["turn"])])
	l.sort_custom(func(x, y): return int(x[0]) * 10000 + int(x[1]) * 100 + int(x[2]) < int(y[0]) * 10000 + int(y[1]) * 100 + int(y[2]))
	st["called"] = l


## A human's answer to a call proposal p (CRules._answer).
static func answer_call(st: Dictionary, b: int, p: Dictionary, accept: bool) -> void:
	var a := int(p["from"])
	var c := int(p.get("vs", -1))
	_answered(st, a, b, c, accept, "" if accept else "refused")


## b answers a's call to its war on c: joins (war on c, "called") or
## refuses (regard and repute costs).
static func _answered(st: Dictionary, a: int, b: int, c: int, accept: bool, why: String) -> void:
	_drop_called(st, a, b, c)
	if accept:
		_rules().event(st, {"k": "call_answered", "from": a, "to": b, "vs": c, "accept": 1, "why": ""})
		if CState.alive(st, c) and not CState.at_war(st, b, c) and not CState.friendly(st, b, c) \
				and not _ai().call("tutorial_shield", st, c):
			_rules().call("declare_war", st, b, c, "called")
		if CState.at_war(st, a, c):
			_kept_faith(st, a, b, c)  # (2026-11-02) answering pays
		return
	_rules().event(st, {"k": "call_answered", "from": a, "to": b, "vs": c, "accept": 0, "why": why})
	_refusal_costs(st, a, b)


static func _refusal_costs(st: Dictionary, a: int, b: int) -> void:
	add_regard(st, a, b, REG_CALL_REFUSED, "call_refused")
	add_repute(st, b, REP_CALL_REFUSED, "call_refused")


## (2026-11-02) The allies a (index order) whose call to their war on c is
## still open for b (a "called" record: the window is CALL_WAIT turns).
static func open_calls(st: Dictionary, b: int, c: int) -> Array:
	var out: Array = []
	for e in st.get("called", []):
		if int(e[1]) == b and int(e[2]) == c and not out.has(int(e[0])):
			out.append(int(e[0]))
	out.sort()
	return out


## (2026-11-02) b's war order on c while a call against c is open (the
## proposal may have lapsed after its turn): the war answers every open
## call (why "called": no unprovoked-war repute) and each counts as kept.
## Returns false when no call is open (the order is an ordinary war).
static func war_answers_call(st: Dictionary, b: int, c: int) -> bool:
	if not on(st):
		return false
	var callers := open_calls(st, b, c)
	if callers.is_empty():
		return false
	var keep: Array = []
	for p in st["proposals"]:
		if not (str(p["what"]) == "call" and int(p["to"]) == b and int(p.get("vs", -1)) == c):
			keep.append(p)
	st["proposals"] = keep
	for a in callers:
		_answered(st, int(a), b, c, true, "")
	return true


static func _drop_called(st: Dictionary, a: int, b: int, c: int) -> void:
	if not st.has("called"):
		return
	var keep: Array = []
	for e in st["called"]:
		if not (int(e[0]) == a and int(e[1]) == b and int(e[2]) == c):
			keep.append(e)
	if keep.is_empty():
		st.erase("called")
	else:
		st["called"] = keep


# -------------------------------------------------------------- passage ---

static func passage_check(st: Dictionary, f: int, g: int) -> String:
	if not on(st):
		return "no passage treaties in this campaign's format"
	var d := CState.dip(st, f, g)
	if d != CState.PEACE and d != CState.TRADE:
		return "make peace first"
	if has_passage(st, f, g):
		return "passage already granted"
	return ""


## g grants f passage through its land for PASSAGE_TURNS turns.
static func grant_passage(st: Dictionary, f: int, g: int) -> void:
	var until := int(st["turn"]) + PASSAGE_TURNS
	st["passage"][g * _n() + f] = until
	_rules().event(st, {"k": "passage", "a": g, "b": f, "until": until})


# -------------------------------------------------- the treaty lines ---

## "" if faction f may raise unit `key` as far as the treaty lines go
## (CData.TREATY_LINES: faction key -> line -> faction keys a trade
## agreement with which unlocks it), else why not.
static func line_why(st: Dictionary, f: int, line: String) -> String:
	if not on(st) or f < 0 or CData.TREATY_LINES.is_empty():
		return ""
	var fk := str(CData.FACTIONS[f]["key"])
	if not CData.TREATY_LINES.has(fk):
		return ""
	var lines: Dictionary = CData.TREATY_LINES[fk]
	if not lines.has(line):
		return ""
	if _trades_with(st, f, lines[line]):
		return ""
	return TREATY_LINE_WHY


## Faction f trades with (or is allied to) one of the faction keys `keys` alive.
static func _trades_with(st: Dictionary, f: int, keys: Array) -> bool:
	for gk in keys:
		var g := CData.faction_index(str(gk))
		if g >= 0 and g != f and CState.alive(st, g) and CState.dip(st, f, g) >= CState.TRADE:
			return true
	return false


## (Native vessels, 2026-11-01) The treaty lines' rule for a ship row: "" when faction f may build ship row
## `row` as far as treaties go, else why not. A row's optional "ally" (faction key -> faction keys) binds
## only the factions it lists: they build the hull while they trade with or are allied to one of those
## (the Miskito's brigantine and England). Before format 10 (no treaties) nothing is refused, as for the lines.
static func ship_why(st: Dictionary, f: int, row: Dictionary) -> String:
	if f < 0 or not row.has("ally"):
		return ""
	var al = (row["ally"] as Dictionary).get(str(CData.FACTIONS[f]["key"]))
	if al == null or not on(st):
		return ""
	if _trades_with(st, f, al):
		return ""
	return "needs a trade agreement or alliance with " + ally_names(al)


## "England", "England or France": the faction names of the keys, in their order.
static func ally_names(keys: Array) -> String:
	var nm: Array = []
	for gk in keys:
		var g := CData.faction_index(str(gk))
		nm.append(CData.faction_name(g) if g >= 0 else str(gk))
	if nm.size() <= 1:
		return "".join(nm)
	return ", ".join(nm.slice(0, nm.size() - 1)) + " or " + str(nm[-1])


static func unit_why(st: Dictionary, f: int, key: String) -> String:
	var ty := UT.index_of(key)
	if ty < 0:
		return ""
	return line_why(st, f, UT.line_of(ty))


# ------------------------------------------------- the starting treaties ---

## A new campaign (CState.new_campaign, after the dip matrix, the teams and
## the fleets): the pack's START_TREATIES. "alliance": allied (and so
## trading) with regard REG_TREATY both ways (logged, no event); "marque":
## CSea.grant for its usual term (needs a pack with ships).
static func start_treaties(st: Dictionary) -> void:
	var n := _n()
	for t in CData.START_TREATIES:
		var a := CData.faction_index(str(t[0]))
		var b := CData.faction_index(str(t[1]))
		if a < 0 or b < 0 or a == b:
			continue
		match str(t[2]):
			"alliance":
				CState.set_dip(st, a, b, CState.ALLIED)
				for p in [[a, b], [b, a]]:
					var i := int(p[0]) * n + int(p[1])
					st["regard"][i] = REG_TREATY
					(st["regard_log"][i] as Array).append([int(st["turn"]), REG_TREATY, "treaty"])
			"marque":
				if st.has("fleets"):
					_sea().call("grant", st, a, b)


## Undo start_treaties on a copy of a NEW campaign (CState.as_format below
## 10: the state an older build made). True if a treaty was undone.
static func undo_start_treaties(st: Dictionary) -> bool:
	var any := false
	for t in CData.START_TREATIES:
		var a := CData.faction_index(str(t[0]))
		var b := CData.faction_index(str(t[1]))
		if a < 0 or b < 0 or a == b:
			continue
		match str(t[2]):
			"alliance":
				if not CState.same_team(st, a, b) and CState.dip(st, a, b) == CState.ALLIED:
					CState.set_dip(st, a, b, CState.PEACE)
					any = true
			"marque":
				if st.has("marques"):
					var keep: Array = []
					for m in st["marques"]:
						if not ((int(m[0]) == a and int(m[1]) == b) or (int(m[0]) == b and int(m[1]) == a)):
							keep.append(m)
					if keep.size() == (st["marques"] as Array).size():
						continue
					any = true
					if keep.is_empty():
						st.erase("marques")
					else:
						st["marques"] = keep
					var s: Dictionary = st["stats"]
					s["marques"] = int(s.get("marques", 0)) - 1
					if int(s["marques"]) <= 0:
						s.erase("marques")
					for k in ["events", "chronicle"]:
						if not st.has(k):
							continue
						var ke: Array = []
						for e in st[k]:
							if not (str(e.get("k", "")) == "marque" and int(e.get("turn", -1)) == int(st["turn"])):
								ke.append(e)
						if k == "chronicle" and ke.is_empty():
							st.erase("chronicle")
						else:
							st[k] = ke
	return any


# ----------------------------------------------------------- end of turn ---

## CRules.end_of_turn: alliances whose notice ran out end; calls sat out
## cost (and an AI caller leaves the alliance); the fade; trespass costs
## (each human army standing in the land of a faction at peace or trade
## with it, not allied, without passage: REG_TRESPASS a turn, one event per
## pair); an AI regarding a trespasser below WAR_LINE declares war on it
## ("trespass"); passage treaties that run out next turn lapse.
static func end_turn(st: Dictionary) -> void:
	if not on(st):
		return
	var n := _n()
	var turn := int(st["turn"])
	# Alliances leaving with notice.
	if st.has("aleaving"):
		for e in (st["aleaving"] as Array).duplicate():
			if turn - int(e[2]) >= ALLIANCE_NOTICE:
				leave_now(st, int(e[0]), int(e[1]), "notice")
	# Calls to arms sat out.
	if st.has("called"):
		for e in (st["called"] as Array).duplicate():
			var a := int(e[0])
			var b := int(e[1])
			var c := int(e[2])
			if not CState.alive(st, a) or not CState.alive(st, b) or not CState.alive(st, c) or not allied(st, a, b) \
					or not CState.at_war(st, a, c) or CState.at_war(st, b, c):
				_drop_called(st, a, b, c)
				continue
			if turn - int(e[3]) < CALL_WAIT:
				continue
			_drop_called(st, a, b, c)
			_rules().event(st, {"k": "call_sat_out", "from": a, "to": b, "vs": c})
			_refusal_costs(st, a, b)
			if not CState.is_human(st, a):
				leave_now(st, a, b, "sat_out")
	_prune_answered(st)  # (2026-11-02) calls kept whose war or alliance is over
	fade(st)
	# Trespass.
	var cnt := PackedInt32Array()
	cnt.resize(n * n)
	cnt.fill(0)
	for a in st["armies"]:
		var f := int(a["f"])
		var o := CState.owner(st, int(a["r"]))
		if o < 0 or o == f or not CState.is_human(st, f) or not CState.alive(st, o):
			continue
		if not may_cross(st, f, o) or has_passage(st, f, o):
			continue
		cnt[o * n + f] += 1
	for i in n * n:
		if cnt[i] == 0:
			continue
		var g := i / n
		var f := i % n
		add_regard(st, g, f, REG_TRESPASS * cnt[i], "trespass")
		_rules().event(st, {"k": "trespass", "f": f, "g": g, "armies": cnt[i]})
	for i in n * n:
		var g := i / n
		var f := i % n
		if cnt[i] > 0 and not CState.is_human(st, g) and regard(st, g, f) < WAR_LINE and not CState.at_war(st, g, f) \
				and not CState.friendly(st, g, f) and not _ai().call("tutorial_shield", st, f):
			_rules().call("declare_war", st, g, f, "trespass")
	# Passage lapses.
	for i in n * n:
		var until := int(st["passage"][i])
		if until > 0 and until <= turn + 1:
			st["passage"][i] = 0
			_rules().event(st, {"k": "passage_end", "a": i / n, "b": i % n})
