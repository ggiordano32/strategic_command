extends RefCounted
## Story campaigns (DESIGN "Story campaign: The Brethren's Due"): a data-driven
## event system in the campaign rules. A story is a script of events
## (campaign/data/story_<key>.gd) with triggers on the state, lines spoken by
## the characters, choices with effects, and running pressures; scripted
## actors (fleets the story moves, not the AI) act on their own clocks. Same
## discipline as the rest of campaign/: integers, the state's RNG, arrays in
## index order, no Nodes; a state without "story" never reaches any of this
## (every hook checks on(st) first), so normal campaigns are byte-identical.
##
## State (only in a story campaign): story {
##   key (the script), y0 (years added to the pack's calendar), act,
##   cap [the captains: human factions the story speaks to; one now, two in
##     co-op later (each pending choice names who answers)],
##   p {purse, owed, heat, favour, haven} (pressures, see the script),
##   flags [names], fired [[event id, turn last fired]], sched [[turn, event
##   id]] (due follow-ups, in order), timers [[name, until turn]],
##   pending [{id, e (event id), t (turn), f (captain answering)}] (choices
##     waiting: the turn cannot resolve until they are answered, like
##     pending battles), next (pending id),
##   log [{n, t, e, c (choice, -1 news)}] (the story so far, last LOG_MAX),
##     ln (log entries ever, for the view's "seen" marker),
##   actors [{k, fl (fleet id), mode ("chase" | "hunt" | "hold" | "goal" |
##     "home"), until (chase: turn), home (region key), x, y (goal cell), ttl
##     (turns left, 0 none)}] (the story's fleets: tagged "sto" = k, left out
##     of the AI's fleet plans),
##   bt [[battle id, tag]] (battles the story opened), plunder0 (the
##     captains' plunder seen), plunder_t (turn of the last plunder), mercy
##     (rescues left for a captain with no ship and no land)}.
## Orders: none. Choices are answered by answer(st, f, pending id, choice),
## a pure function like CTurn.apply_battle (the client runs it and, online,
## would upload the result).

const CData := preload("res://campaign/cdata.gd")
const CState := preload("res://campaign/cstate.gd")
const CGrid := preload("res://campaign/cgrid.gd")
const CFleet := preload("res://campaign/cfleet.gd")
const CSea := preload("res://campaign/csea.gd")
const CCaptain := preload("res://campaign/ccaptain.gd")
const CStorm := preload("res://campaign/cstorm.gd")
const UT := preload("res://sim/unit_types.gd")

## The scripts by key.
const SCRIPTS := {"brethren": preload("res://campaign/data/story_brethren.gd")}
const LOG_MAX := 200
const P_MAX := 100


static func _rules() -> GDScript:
	return load("res://campaign/crules.gd")


static func on(st: Dictionary) -> bool:
	return st.has("story")


static func S(st: Dictionary) -> Dictionary:
	return st["story"]


static func script_of(st: Dictionary) -> GDScript:
	return SCRIPTS.get(str(S(st).get("key", "")), null)


static func _c(st: Dictionary, name: String, default = 0):
	var sc := script_of(st)
	if sc == null:
		return default
	var m := sc.get_script_constant_map()
	return m.get(name, default)


static func events_of(st: Dictionary) -> Array:
	return _c(st, "EVENTS", [])


## The event with id `id` ({} none).
static func event_def(st: Dictionary, id: String) -> Dictionary:
	for e in events_of(st):
		if str(e["id"]) == id:
			return e
	return {}


static func _event_index(st: Dictionary, id: String) -> int:
	var list := events_of(st)
	for i in list.size():
		if str(list[i]["id"]) == id:
			return i
	return -1


# ------------------------------------------------------------------ start ---

## A new story campaign: the pack's campaign with the script's start (the
## player is its PLAYER faction), its first events fired.
static func new_story(p_name: String, p_seed: int, settings: Dictionary = {}, key: String = "brethren") -> Dictionary:
	var sc: GDScript = SCRIPTS[key]
	var m := sc.get_script_constant_map()
	var stt: Dictionary = (m["START"] as Dictionary).get("settings", {}).duplicate()
	for k in settings:
		stt[k] = settings[k]
	CData.use_pack("west")
	var pf := CData.faction_index(str(m["PLAYER"]))
	var st := CState.new_campaign(p_name, p_seed, [pf], stt, [], "west")
	_setup(st, key, pf)
	return st


static func _setup(st: Dictionary, key: String, pf: int) -> void:
	var sc: GDScript = SCRIPTS[key]
	var m := sc.get_script_constant_map()
	var start: Dictionary = m["START"]
	var y0 := int(m.get("START_YEAR", CData.START_YEAR)) - CData.START_YEAR
	st["story"] = {"key": key, "y0": y0, "act": 0, "cap": [pf], "p": (m["PRESSURES"] as Dictionary).duplicate(),
		"flags": [], "fired": [], "sched": [], "timers": [], "pending": [], "next": 1, "log": [], "ln": 0,
		"actors": [], "bt": [], "plunder0": 0, "plunder_t": -100, "mercy": int(m.get("MERCY", 0))}
	CData.year_shift = y0
	var fs: Dictionary = st["factions"][pf]
	fs["treasury"] = int(start.get("treasury", 0))
	fs["infamy"] = int(start.get("infamy", 0))
	# The player's lands: only the ones the script keeps (the rest go independent).
	var keep: Array = start.get("keep_regions", [])
	for r in CData.region_count():
		if CState.owner(st, r) == pf and not keep.has(str(CData.REGIONS[r]["key"])):
			st["regions"][r]["owner"] = -1
	var arm: Array = []
	for a in st["armies"]:
		if int(a["f"]) != pf:
			arm.append(a)
	st["armies"] = arm
	CFleet.drop_faction(st, pf)
	if st.has("captains"):
		var cs: Array = []
		for c in st["captains"]:
			if int(c["f"]) != pf:
				cs.append(c)
		st["captains"] = cs
	for k in start.get("peace", []):
		var g := CData.faction_index(str(k))
		if g >= 0 and CState.dip(st, pf, g) == CState.WAR:
			CState.set_dip(st, pf, g, CState.PEACE)
	# The flagship off Port Royal with a company aboard, under the captain.
	var c0 := _sea_near(_pos_cell(st, start["at"]))
	var sh: Dictionary = (start["ship"] as Dictionary).duplicate()
	var fl := CFleet._new_fleet(st, pf, c0, [_ship(sh)])
	for u in start.get("aboard", []):
		var a := _new_army(st, pf, CGrid.region(_land_near(c0)), [str(u[0])], int(u[1]))
		(fl["carry"] as Array).append(a)
	var cap := CCaptain._new(st, pf, int(fl["id"]))
	cap["nm"] = str(m.get("CAPTAIN", "The Captain"))
	cap["fame"] = 5
	# The scripted actors.
	for ad in start.get("actors", []):
		var f := CData.faction_index(str(ad["f"]))
		var at = ad["at"]
		var c := -1
		if at is String:
			c = CFleet.dock(CData.region_index(str(at)))
		else:
			c = _sea_near(_pos_cell(st, at))
		var ships: Array = []
		for s in ad["ships"]:
			ships.append(_ship(s))
		var afl := CFleet._new_fleet(st, f, c, ships)
		afl["sto"] = str(ad["k"])
		var en := {"k": str(ad["k"]), "fl": int(afl["id"]), "mode": str(ad.get("mode", "hold")), "ttl": 0}
		if ad.has("until"):
			en["until"] = int(ad["until"])
		if ad.has("home"):
			en["home"] = str(ad["home"])
		(S(st)["actors"] as Array).append(en)
	check(st)


static func _ship(d: Dictionary) -> Dictionary:
	var s := {"t": str(d["t"]), "h": int(d.get("h", 100)), "c": int(d.get("c", 100))}
	for k in ["nm", "g"]:
		if d.has(k):
			s[k] = d[k]
	return s


## A new army of faction f in region r of `keys`, each unit at pct % of its men.
static func _new_army(st: Dictionary, f: int, r: int, keys: Array, pct: int = 100) -> Dictionary:
	var units: Array = []
	for k in keys:
		var ty := UT.index_of(str(k))
		if ty < 0:
			continue
		units.append({"t": str(k), "n": maxi(1, UT.size_of(ty) * pct / 100)})
	var fs: Dictionary = st["factions"][f]
	var a := {"id": _rules().new_army_id(st, f), "f": f, "r": maxi(r, 0), "units": units, "from": -1, "moved": 0, "busy": 0}
	fs["next_army"] = int(fs["next_army"]) + 1
	CState.army_defaults(a)
	CState.place(a, CState.field_cell(maxi(r, 0)))
	CState.army_defaults6(a)
	return a


# -------------------------------------------------------------- queries ---

static func captains(st: Dictionary) -> Array:
	return S(st).get("cap", [])


## The captain the story speaks to first (-1 none).
static func player(st: Dictionary) -> int:
	var c := captains(st)
	return int(c[0]) if not c.is_empty() else -1


static func p(st: Dictionary, k: String) -> int:
	return int((S(st)["p"] as Dictionary).get(k, 0))


static func add_p(st: Dictionary, k: String, n: int) -> void:
	var pp: Dictionary = S(st)["p"]
	var hi := 1 << 30 if k == "owed" else P_MAX
	pp[k] = clampi(int(pp.get(k, 0)) + n, 0, hi)


## The Armada's attention: the captains' infamy plus Spain's grudge (0-100).
static func attention(st: Dictionary) -> int:
	var inf := 0
	for f in captains(st):
		inf = maxi(inf, CSea.infamy(st, int(f)))
	return clampi(inf + p(st, "heat"), 0, P_MAX)


static func flag(st: Dictionary, nm: String) -> bool:
	return (S(st)["flags"] as Array).has(nm)


static func set_flag(st: Dictionary, nm: String) -> void:
	if not flag(st, nm):
		(S(st)["flags"] as Array).append(nm)


static func timer_on(st: Dictionary, nm: String) -> bool:
	for t in S(st)["timers"]:
		if str(t[0]) == nm and int(st["turn"]) < int(t[1]):
			return true
	return false


static func timer_until(st: Dictionary, nm: String) -> int:
	for t in S(st)["timers"]:
		if str(t[0]) == nm:
			return int(t[1])
	return -1


## Story choices are waiting: the turn cannot resolve.
static func blocked(st: Dictionary) -> bool:
	return on(st) and not (S(st)["pending"] as Array).is_empty()


## The choices waiting for faction f (any captain with f < 0), oldest first.
static func pending_for(st: Dictionary, f: int = -1) -> Array:
	if not on(st):
		return []
	var out: Array = []
	for pe in S(st)["pending"]:
		if f < 0 or int(pe["f"]) == f:
			out.append(pe)
	return out


static func actor(st: Dictionary, k: String) -> Dictionary:
	for a in S(st)["actors"]:
		if str(a["k"]) == k:
			return a
	return {}


static func actor_fleet(st: Dictionary, k: String) -> Dictionary:
	var a := actor(st, k)
	if a.is_empty():
		return {}
	var fl := CFleet.fleet(st, int(a["fl"]))
	if fl.is_empty() or (fl["ships"] as Array).is_empty():
		return {}
	return fl


## The captains' fleets with ships, by id.
static func player_fleets(st: Dictionary) -> Array:
	var out: Array = []
	for fl in CFleet.fleets(st):
		if captains(st).has(int(fl["f"])) and not (fl["ships"] as Array).is_empty():
			out.append(fl)
	return out


## Captain f's flagship (its lowest fleet id with ships), {} none.
static func flagship(st: Dictionary, f: int) -> Dictionary:
	for fl in CFleet.fleets_of(st, f):
		if not (fl["ships"] as Array).is_empty():
			return fl
	return {}


## Faction f is a story captain kept alive with nothing left (a rescue is
## due: crules.check_eliminations spares it until end_turn's rescue).
static func spared(st: Dictionary, f: int) -> bool:
	return on(st) and captains(st).has(f) and int(S(st).get("mercy", 0)) > 0


# --------------------------------------------------------------- positions ---

## The cell of [lon, lat] (1/100 degree; the pack's window), or a region key
## (its settlement), or ["player", dx, dy] (cells from the first captain's
## flagship), or "lair" (the script's LAIR).
static func _pos_cell(st: Dictionary, pos) -> int:
	if pos is String:
		if str(pos) == "lair":
			return _pos_cell(st, _c(st, "LAIR", [0, 0]))
		var r := CData.region_index(str(pos))
		return CFleet.dock(r) if r >= 0 and CFleet.dock(r) >= 0 else (CGrid.site(r) if r >= 0 else -1)
	var arr: Array = pos
	if arr.size() == 3 and str(arr[0]) == "player":
		var fl := flagship(st, player(st))
		if fl.is_empty():
			return -1
		return CGrid.at(clampi(int(fl["x"]) + int(arr[1]), 0, CGrid.width() - 1), clampi(int(fl["y"]) + int(arr[2]), 0, CGrid.height() - 1))
	# The West window: lon -98.5 .. -58.5, lat 31.5 .. 8 (tools/geo/carib.json).
	var x := (int(arr[0]) + 9850) * CGrid.width() / 4000
	var y := (3150 - int(arr[1])) * CGrid.height() / 2350
	return CGrid.at(clampi(x, 0, CGrid.width() - 1), clampi(y, 0, CGrid.height() - 1))


## The open-sea cell nearest c (rings outward, lowest index on a tie), -1 none.
static func _sea_near(c: int) -> int:
	if c < 0:
		return -1
	if CFleet.is_sea(c):
		return c
	for rad in range(1, 20):
		var best := -1
		var bd := 1 << 30
		for j in CGrid.disc(c, rad):
			if not CFleet.is_sea(j):
				continue
			var d := CGrid.d2(j, c)
			if d < bd or (d == bd and j < best):
				bd = d
				best = j
		if best >= 0:
			return best
	return -1


## The land cell (with a region) nearest c, -1 none.
static func _land_near(c: int) -> int:
	for rad in range(1, 20):
		var best := -1
		var bd := 1 << 30
		for j in CGrid.disc(c, rad):
			if CFleet.is_sea(j) or CGrid.region(j) < 0:
				continue
			var d := CGrid.d2(j, c)
			if d < bd or (d == bd and j < best):
				bd = d
				best = j
		if best >= 0:
			return best
	return -1


# ------------------------------------------------------------- conditions ---

static func _list(v) -> Array:
	return v if v is Array else [v]


static func _cond(st: Dictionary, w: Dictionary) -> bool:
	var t := int(st["turn"])
	var pf := player(st)
	if w.has("turn"):
		var tw: Array = w["turn"]
		if t < int(tw[0]) or (int(tw[1]) >= 0 and t > int(tw[1])):
			return false
	if w.has("flag"):
		for nm in _list(w["flag"]):
			if not flag(st, str(nm)):
				return false
	if w.has("noflag"):
		for nm in _list(w["noflag"]):
			if flag(st, str(nm)):
				return false
	if w.has("p_ge") and p(st, str(w["p_ge"][0])) < int(w["p_ge"][1]):
		return false
	if w.has("p_lt") and p(st, str(w["p_lt"][0])) >= int(w["p_lt"][1]):
		return false
	if w.has("att_ge") and attention(st) < int(w["att_ge"]):
		return false
	if w.has("att_lt") and attention(st) >= int(w["att_lt"]):
		return false
	if w.has("owns") and not captains(st).has(CState.owner(st, CData.region_index(str(w["owns"])))):
		return false
	if w.has("lost") and captains(st).has(CState.owner(st, CData.region_index(str(w["lost"])))):
		return false
	if w.has("near") and not _near(st, CData.region_index(str(w["near"][0])), int(w["near"][1])):
		return false
	if w.has("season") and not CStorm.season(t):
		return false
	if w.has("storm") and CStorm.storms(st).is_empty():
		return false
	if w.has("siege") and not _siege(st):
		return false
	if w.has("plunder") and _plunder(st) <= 0:
		return false
	if w.has("plundered_in") and t - int(S(st)["plunder_t"]) > int(w["plundered_in"]):
		return false
	if w.has("not_plundered_in") and t - int(S(st)["plunder_t"]) <= int(w["not_plundered_in"]):
		return false
	if w.has("actor"):
		var alive := not actor_fleet(st, str(w["actor"][0])).is_empty()
		if alive != (str(w["actor"][1]) == "alive"):
			return false
	if w.has("gold_ge") and (pf < 0 or int(st["factions"][pf]["treasury"]) < int(w["gold_ge"])):
		return false
	if w.has("timer") and not timer_on(st, str(w["timer"])):
		return false
	if w.has("ships_ge"):
		var n := 0
		for fl in player_fleets(st):
			n += (fl["ships"] as Array).size()
		if n < int(w["ships_ge"]):
			return false
	return true


## A captain's fleet (or army) within `cells` of region r's harbour (or its
## settlement inland).
static func _near(st: Dictionary, r: int, cells: int) -> bool:
	if r < 0:
		return false
	var at := CFleet.harbour(r)
	if at < 0:
		at = CGrid.site(r)
	for fl in player_fleets(st):
		if CGrid.cheb(CFleet.cell(fl), at) <= cells:
			return true
	for a in st["armies"]:
		if captains(st).has(int(a["f"])) and CGrid.cheb(CState.cell(a), at) <= cells:
			return true
	return false


static func _siege(st: Dictionary) -> bool:
	for sg in st.get("sieges", []):
		if captains(st).has(int(sg["f"])) or captains(st).has(CState.owner(st, int(sg["r"]))):
			return true
	return false


static func _plunder(st: Dictionary) -> int:
	var n := 0
	for f in captains(st):
		n += int(st["factions"][int(f)].get("plunder", 0))
	return n


## "" if captain f may take choice k of pending entry pid, else why not.
static func answer_check(st: Dictionary, f: int, pid: int, k: int) -> String:
	if not on(st):
		return "not a story campaign"
	var pe := _pending(st, pid)
	if pe.is_empty():
		return "no such choice"
	if int(pe["f"]) != f:
		return "not yours to answer"
	var ev := event_def(st, str(pe["e"]))
	var ch: Array = ev.get("choices", [])
	if k < 0 or k >= ch.size():
		return "no such choice"
	var need: Dictionary = (ch[k] as Dictionary).get("need", {})
	if not need.is_empty() and not _cond(st, need):
		return str((ch[k] as Dictionary).get("why", "not possible now"))
	return ""


static func _pending(st: Dictionary, pid: int) -> Dictionary:
	for pe in S(st)["pending"]:
		if int(pe["id"]) == pid:
			return pe
	return {}


# ---------------------------------------------------------------- firing ---

## Fire every event whose time has come: due follow-ups first (in order),
## then the triggers (in script order); effects may schedule more for now,
## so it runs a few passes.
static func check(st: Dictionary) -> void:
	if not on(st):
		return
	var t := int(st["turn"])
	for pass_i in 4:
		var any := false
		var due: Array = []
		var later: Array = []
		for sc in S(st)["sched"]:
			if int(sc[0]) <= t:
				due.append(sc)
			else:
				later.append(sc)
		S(st)["sched"] = later
		for sc in due:
			var i := _event_index(st, str(sc[1]))
			if i < 0:
				continue
			var ev: Dictionary = events_of(st)[i]
			if ev.has("if") and not _cond(st, ev["if"]):
				continue
			_fire(st, i)
			any = true
		var list := events_of(st)
		for i in list.size():
			var ev: Dictionary = list[i]
			if not ev.has("when") or not _eligible(st, ev):
				continue
			if not _cond(st, ev["when"]):
				continue
			_fire(st, i)
			any = true
		if not any:
			break


## Event ev may fire now: never yet, or (every N) N turns after it last did
## and no choice of it is still waiting.
static func _eligible(st: Dictionary, ev: Dictionary) -> bool:
	var last := _last_fired(st, str(ev["id"]))
	if last == -1000:
		return true
	if not ev.has("every"):
		return false
	for pe in S(st)["pending"]:
		if str(pe["e"]) == str(ev["id"]):
			return false
	return int(st["turn"]) - last >= int(ev["every"])


static func _last_fired(st: Dictionary, id: String) -> int:
	for fr in S(st)["fired"]:
		if str(fr[0]) == id:
			return int(fr[1])
	return -1000


static func _fire(st: Dictionary, i: int) -> void:
	var ev: Dictionary = events_of(st)[i]
	var id := str(ev["id"])
	var t := int(st["turn"])
	var found := false
	for fr in S(st)["fired"]:
		if str(fr[0]) == id:
			fr[1] = t
			found = true
	if not found:
		(S(st)["fired"] as Array).append([id, t])
	var pf := player(st)
	if ev.has("chron"):
		_rules().event(st, {"k": "story", "e": id, "f": pf})
	_fx(st, pf, ev.get("fx", []))
	if (ev.get("choices", []) as Array).is_empty():
		_log(st, id, -1)
		return
	var n := int(S(st)["next"])
	S(st)["next"] = n + 1
	(S(st)["pending"] as Array).append({"id": n, "e": id, "t": t, "f": pf})


static func _log(st: Dictionary, id: String, c: int) -> void:
	var n := int(S(st)["ln"]) + 1
	S(st)["ln"] = n
	var lg: Array = S(st)["log"]
	lg.append({"n": n, "t": int(st["turn"]), "e": id, "c": c})
	if lg.size() > LOG_MAX:
		S(st)["log"] = lg.slice(lg.size() - LOG_MAX)


## Captain f answers pending choice pid with choice k: its effects apply,
## then any events they set off. Returns the new state (the same state when
## the answer is refused). A battle opened by a choice must be fought before
## the turn goes on (phase "battles").
static func answer(st_in: Dictionary, f: int, pid: int, k: int) -> Dictionary:
	CData.use_state(st_in)
	var st := CState.copy(st_in)
	if answer_check(st, f, pid, k) != "":
		return st
	var pe := _pending(st, pid)
	(S(st)["pending"] as Array).erase(pe)
	var ev := event_def(st, str(pe["e"]))
	var ch: Dictionary = ev["choices"][k]
	_log(st, str(pe["e"]), k)
	_fx(st, f, ch.get("fx", []))
	check(st)
	_after_fx(st)
	return st


## A battle opened by an effect: the turn waits for it.
static func _after_fx(st: Dictionary) -> void:
	if str(st["phase"]) == "plan" and not (st["battles"] as Array).is_empty():
		st["phase"] = "battles"


# --------------------------------------------------------------- effects ---

## Apply effects fx for captain f. Effects:
##   gold n | plunder n (counts as plunder) | p pressure n | infamy n |
##   fame n (the captain's most famous) | flag nm | unflag nm |
##   sched event n (fires n turns from now; 0: at once) | timer nm turns |
##   act n (also flag "act<n>") | crew pct (every ship's crew and every
##   company's men) | hull pct | unit key count region (companies join an
##   army of ours there) | lose_ship (the weakest; the last only loses crew)
##   | gamble pct win lose (schedule one of two events) | gamble_fame pct ..
##   (pct + fame / 2) | spawn actor faction pos [ships] ttl mode | actor_hull
##   actor pct [crew pct] (its ships' hull and crew to pct % of what they are) | place
##   actor pos | goal actor pos | home actor | chase actor | hold actor |
##   release actor | remove actor | join actor name fame (its fleet becomes
##   the captain's) | sea_battle actor (now, with the flagship) | raid
##   faction region [units] tag (lands and storms it now) | sack region |
##   voyage pos / voyage_r region (the flagship's stored voyage) | storm (one
##   east of the flagship if none is at sea) | dip faction "war" | "peace".
static func _fx(st: Dictionary, f: int, fx: Array) -> void:
	for e in fx:
		var a: Array = e
		match str(a[0]):
			"gold":
				if f >= 0:
					var fs: Dictionary = st["factions"][f]
					fs["treasury"] = int(fs["treasury"]) + int(a[1])
			"plunder":
				CSea.gain(st, f, int(a[1]))
			"p":
				add_p(st, str(a[1]), int(a[2]))
			"infamy":
				CSea.add_infamy(st, f, int(a[1]))
			"fame":
				var best := {}
				for c in CCaptain.of_faction(st, f):
					if best.is_empty() or int(c["fame"]) > int(best["fame"]):
						best = c
				CCaptain.add_fame(st, best, int(a[1]))
			"flag":
				set_flag(st, str(a[1]))
			"unflag":
				(S(st)["flags"] as Array).erase(str(a[1]))
			"sched":
				_sched(st, str(a[1]), int(st["turn"]) + int(a[2]))
			"timer":
				var tl: Array = S(st)["timers"]
				for tm in tl:
					if str(tm[0]) == str(a[1]):
						tl.erase(tm)
						break
				tl.append([str(a[1]), int(st["turn"]) + int(a[2])])
			"act":
				S(st)["act"] = int(a[1])
				set_flag(st, "act%d" % int(a[1]))
			"crew":
				_crew(st, f, int(a[1]))
			"hull":
				for fl in CFleet.fleets_of(st, f):
					for sh in fl["ships"]:
						sh["h"] = clampi(int(sh["h"]) * (100 + int(a[1])) / 100, 5, 100)
			"unit":
				_units(st, f, str(a[1]), int(a[2]), CData.region_index(str(a[3])))
			"lose_ship":
				_lose_ship(st, f)
			"gamble", "gamble_fame":
				var pct := int(a[1])
				if str(a[0]) == "gamble_fame":
					pct += CCaptain.best_fame(st, f) / 2
				var won := CState.rand(st, 100) < mini(pct, 90)
				_sched(st, str(a[2]) if won else str(a[3]), int(st["turn"]))
			"spawn":
				_spawn(st, a)
			"actor_hull":
				var hfl := actor_fleet(st, str(a[1]))
				if not hfl.is_empty():
					for sh in hfl["ships"]:
						sh["h"] = clampi(int(sh["h"]) * int(a[2]) / 100, 5, 100)
						if a.size() > 3:
							sh["c"] = clampi(int(sh["c"]) * int(a[3]) / 100, 5, 100)
			"place":
				var pfl := actor_fleet(st, str(a[1]))
				var pc := _sea_near(_pos_cell(st, a[2]))
				if not pfl.is_empty() and not pfl.has("busy") and pc >= 0:
					CFleet.place(pfl, pc)
					CFleet._drop_voyage(pfl)
					var ac := actor(st, str(a[1]))
					ac["mode"] = "hold"
			"goal":
				var ag := actor(st, str(a[1]))
				var gc := _sea_near(_pos_cell(st, a[2]))
				if not ag.is_empty() and gc >= 0:
					ag["mode"] = "goal"
					ag["x"] = CGrid.cx(gc)
					ag["y"] = CGrid.cy(gc)
			"home":
				var ah := actor(st, str(a[1]))
				if not ah.is_empty():
					if ah.has("home"):
						ah["mode"] = "home"
					else:
						_release(st, str(a[1]))
			"chase", "hold", "hunt":
				var am := actor(st, str(a[1]))
				if not am.is_empty():
					am["mode"] = str(a[0])
			"release":
				_release(st, str(a[1]))
			"remove":
				var rf := actor_fleet(st, str(a[1]))
				if not rf.is_empty() and not rf.has("busy"):
					(st["fleets"] as Array).erase(rf)
				_drop_actor(st, str(a[1]))
			"join":
				_join(st, f, a)
			"sea_battle":
				_sea_battle(st, f, str(a[1]))
			"raid":
				_raid(st, a)
			"sack":
				_sack(st, CData.region_index(str(a[1])))
			"voyage", "voyage_r":
				var fl := flagship(st, f)
				var vc := _sea_near(_pos_cell(st, a[1]))
				if str(a[0]) == "voyage_r":
					vc = CFleet.dock(CData.region_index(str(a[1])))
				if not fl.is_empty() and vc >= 0 and not fl.has("busy"):
					fl["dest_x"] = CGrid.cx(vc)
					fl["dest_y"] = CGrid.cy(vc)
					fl.erase("tgt")
					fl.erase("land")
					fl.erase("route")
					fl.erase("rgoal")
			"storm":
				_storm(st, f)
			"dip":
				var g := CData.faction_index(str(a[1]))
				if g >= 0 and f >= 0:
					if str(a[2]) == "war" and not CState.at_war(st, f, g):
						_rules().declare_war(st, f, g)
					elif str(a[2]) == "peace" and CState.at_war(st, f, g):
						_rules().make_peace(st, f, g)
			_:
				push_warning("story: unknown effect %s" % str(a[0]))


static func _sched(st: Dictionary, id: String, t: int) -> void:
	var sl: Array = S(st)["sched"]
	var i := 0
	while i < sl.size() and int(sl[i][0]) <= t:
		i += 1
	sl.insert(i, [t, id])


static func _crew(st: Dictionary, f: int, pct: int) -> void:
	for fl in CFleet.fleets_of(st, f):
		for sh in fl["ships"]:
			sh["c"] = clampi(int(sh["c"]) * (100 + pct) / 100, 5, 100)
		for a in fl["carry"]:
			for u in a["units"]:
				u["n"] = maxi(1, int(u["n"]) * (100 + pct) / 100)
	for a in st["armies"]:
		if int(a["f"]) == f:
			for u in a["units"]:
				u["n"] = maxi(1, int(u["n"]) * (100 + pct) / 100)


## `count` companies of `key` join captain f's army in region r (one standing
## in or by the settlement), else a new army there (only in a region of ours).
static func _units(st: Dictionary, f: int, key: String, count: int, r: int) -> void:
	if f < 0 or r < 0 or CState.owner(st, r) != f or UT.index_of(key) < 0:
		return
	var site := CGrid.site(r)
	var into := {}
	for a in st["armies"]:
		if int(a["f"]) == f and int(a["busy"]) == 0 and CGrid.cheb(CState.cell(a), site) <= 1 \
				and CState.unit_count(a) + count <= CData.ARMY_MAX:
			into = a
			break
	var keys: Array = []
	for i in count:
		keys.append(key)
	if into.is_empty():
		var na := _new_army(st, f, r, keys)
		CState.place(na, site)
		_rules()._insert_army(st, na)
		return
	for k in keys:
		(into["units"] as Array).append({"t": k, "n": UT.size_of(UT.index_of(k))})


static func _lose_ship(st: Dictionary, f: int) -> void:
	var n := 0
	var best := {}
	var bk := -1
	var bp := 1 << 30
	for fl in CFleet.fleets_of(st, f):
		if fl.has("busy"):
			continue
		for k in (fl["ships"] as Array).size():
			n += 1
			var pw := CFleet.ship_power(fl["ships"][k])
			if pw < bp:
				bp = pw
				best = fl
				bk = k
	if n <= 1:
		_crew(st, f, -30)
		return
	if bk >= 0:
		(best["ships"] as Array).remove_at(bk)
		if (best["ships"] as Array).is_empty() and (best["carry"] as Array).is_empty():
			(st["fleets"] as Array).erase(best)


## ["spawn", actor, faction, pos, [ships], ttl, mode]: a fleet the story moves.
static func _spawn(st: Dictionary, a: Array) -> void:
	var k := str(a[1])
	if not actor_fleet(st, k).is_empty():
		return
	var f := CData.faction_index(str(a[2]))
	var c := _sea_near(_pos_cell(st, a[3]))
	if f < 0 or c < 0 or not CState.alive(st, f):
		return
	var ships: Array = []
	for s in a[4]:
		ships.append(_ship(s))
	var fl := CFleet._new_fleet(st, f, c, ships)
	fl["sto"] = k
	_drop_actor(st, k)
	var en := {"k": k, "fl": int(fl["id"]), "mode": str(a[6]) if a.size() > 6 else "hold", "ttl": int(a[5]) if a.size() > 5 else 0}
	(S(st)["actors"] as Array).append(en)
	(S(st)["flags"] as Array).erase("gone_" + k)


static func _drop_actor(st: Dictionary, k: String) -> void:
	var list: Array = S(st)["actors"]
	for i in list.size():
		if str(list[i]["k"]) == k:
			list.remove_at(i)
			return


## The actor's fleet goes back to its faction's AI.
static func _release(st: Dictionary, k: String) -> void:
	var a := actor(st, k)
	if a.is_empty():
		return
	var fl := CFleet.fleet(st, int(a["fl"]))
	if not fl.is_empty():
		fl.erase("sto")
	_drop_actor(st, k)


## ["join", actor, name, fame]: the actor's fleet sails for captain f under
## its own captain.
static func _join(st: Dictionary, f: int, a: Array) -> void:
	var fl := actor_fleet(st, str(a[1]))
	if fl.is_empty() or fl.has("busy") or f < 0:
		return
	fl["f"] = f
	fl.erase("sto")
	CFleet._drop_voyage(fl)
	_drop_actor(st, str(a[1]))
	var c := CCaptain._new(st, f, int(fl["id"]))
	c["nm"] = str(a[2])
	c["fame"] = int(a[3])
	_rules().event(st, {"k": "story", "e": "join_" + str(a[1]), "f": f})


## A sea battle now between captain f's flagship and the actor's fleet (it
## comes alongside if it is not already near).
static func _sea_battle(st: Dictionary, f: int, k: String) -> void:
	var fl := flagship(st, f)
	var en := actor_fleet(st, k)
	if fl.is_empty() or en.is_empty() or fl.has("busy") or en.has("busy"):
		return
	var c := CFleet.cell(fl)
	if not CGrid.within(c, CFleet.cell(en), CFleet.FLEET_ZONE):
		var best := -1
		for rad in range(1, CFleet.FLEET_ZONE + 1):
			for j in CGrid.disc(c, rad):
				if CFleet.is_sea(j) and j != c and CGrid.within(c, j, CFleet.FLEET_ZONE):
					if best < 0 or j < best:
						best = j
			if best >= 0:
				break
		if best < 0:
			return
		CFleet.place(en, best)
	var before := int(st["next_battle"])
	CFleet.sea_battle(st, fl, [en], c)
	if int(st["next_battle"]) > before:
		(S(st)["bt"] as Array).append([before, k])


## ["raid", faction, region, [units], tag]: an army of faction lands beside
## the settlement and storms it now (a battle, tagged).
static func _raid(st: Dictionary, a: Array) -> void:
	var f := CData.faction_index(str(a[1]))
	var r := CData.region_index(str(a[2]))
	if f < 0 or r < 0 or not CState.alive(st, f) or not CState.at_war(st, f, CState.owner(st, r)):
		return
	if not CState.battle_at(st, r).is_empty():
		return
	var cell := -1
	for k in 8:
		var c := CState.ring_cell(r, k)
		var free := true
		for x in st["armies"]:
			if CState.cell(x) == c:
				free = false
		if free and c != CGrid.site(r):
			cell = c
			break
	if cell < 0:
		return
	var army := _new_army(st, f, r, a[3])
	CState.place(army, cell)
	_rules()._insert_army(st, army)
	var b: Dictionary = _rules()._assault6(st, r, army)
	if b.is_empty():
		return
	_rules().add_reinforcements(st, b)
	b.erase("new")
	(S(st)["bt"] as Array).append([int(b["id"]), str(a[4])])
	_rules().event(st, {"k": "story", "e": "raid", "f": f, "r": r})


## A story sack of region r: every building down a level, the garrison
## thinned, the owner's treasury robbed.
static func _sack(st: Dictionary, r: int) -> void:
	if r < 0:
		return
	var rs: Dictionary = st["regions"][r]
	var keep: Array = []
	for s in rs["slots"]:
		if int(s[1]) > 1:
			keep.append([int(s[0]), int(s[1]) - 1])
	rs["slots"] = keep
	rs["gar"] = mini(int(rs["gar"]), 40)
	var o := CState.owner(st, r)
	if o >= 0:
		var fs: Dictionary = st["factions"][o]
		fs["treasury"] = int(fs["treasury"]) - mini(maxi(int(fs["treasury"]), 0) * 15 / 100, 600)


## A hurricane east of captain f's flagship, heading west, if none is at sea.
static func _storm(st: Dictionary, f: int) -> void:
	if not CStorm.storms(st).is_empty():
		return
	var fl := flagship(st, f)
	if fl.is_empty():
		return
	var x := clampi(int(fl["x"]) + 18, 1, CGrid.width() - 2)
	var y := clampi(int(fl["y"]) - 1, 1, CGrid.height() - 2)
	var t := int(st["turn"])
	var names: Array = CData.ship_const("STORM_NAMES", ["San Lorenzo"])
	var s := {"id": int(st.get("next_storm", 1)), "px": x * 100 + 50, "py": y * 100 + 50, "h": 12, "v": 3200, "r": 5,
		"life": 2, "born": t, "yr": CStorm.year(t), "nm": str(names[CState.rand(st, names.size())]), "tr": [[x, y]],
		"lost": [], "ports": 0, "men": 0, "gold": 0}
	st["next_storm"] = int(s["id"]) + 1
	if not st.has("storms"):
		st["storms"] = []
	(st["storms"] as Array).append(s)
	_rules().event(st, {"k": "storm", "id": int(s["id"]), "nm": str(s["nm"]), "yr": int(s["yr"]), "x": x, "y": y})


# ---------------------------------------------------------- the turn hooks ---

## Step 5 of the turn (CTurn.resolve_turn, with the AI's voyages): the
## story's fleets sail by their modes. chase: the nearest captain's fleet
## (until a turn, then home); hunt (the Armada): a captain's fleet in reach
## while the attention is high, else home; goal: a cell, then hold; home:
## its home port, then back to its faction's AI.
static func actor_moves(st: Dictionary, fmoves: Array) -> void:
	if not on(st):
		return
	var t := int(st["turn"])
	for a in (S(st)["actors"] as Array).duplicate():
		var fl := actor_fleet(st, str(a["k"]))
		if fl.is_empty() or fl.has("busy") or int(fl.get("moved", 0)) != 0:
			continue
		var f := int(fl["f"])
		var md := str(a["mode"])
		if md == "chase" and a.has("until") and t > int(a["until"]):
			md = "home"
			a["mode"] = "home"
		match md:
			"chase":
				var tg := _nearest_foe(st, fl, 1 << 20)
				if not tg.is_empty():
					fmoves.append([int(fl["id"]), -1, f, 0, int(tg["id"])])
			"hunt":
				var att := attention(st)
				var tg2 := {}
				if att >= int(_c(st, "ARMADA_HUNT_ATT", 35)):
					tg2 = _nearest_foe(st, fl, int(_c(st, "ARMADA_RANGE", 25)) + att)
				if not tg2.is_empty():
					fmoves.append([int(fl["id"]), -1, f, 0, int(tg2["id"])])
				else:
					var hd := CFleet.dock(CData.region_index(str(a.get("home", ""))))
					if hd >= 0 and CGrid.cheb(CFleet.cell(fl), hd) > 2:
						fmoves.append([int(fl["id"]), hd, f, 0, -1])
			"goal":
				var gc := CGrid.at(int(a.get("x", -1)), int(a.get("y", -1)))
				if gc >= 0 and CGrid.cheb(CFleet.cell(fl), gc) > 1:
					fmoves.append([int(fl["id"]), gc, f, 0, -1])
				else:
					a["mode"] = "hold"
			"home":
				var hd2 := CFleet.dock(CData.region_index(str(a.get("home", ""))))
				if hd2 < 0 or CGrid.cheb(CFleet.cell(fl), hd2) <= 2:
					_release(st, str(a["k"]))
				else:
					fmoves.append([int(fl["id"]), hd2, f, 0, -1])


## The nearest captain's fleet at war with fl's faction within `cells`
## (Chebyshev), not in a battle ({} none; ties: the lowest id).
static func _nearest_foe(st: Dictionary, fl: Dictionary, cells: int) -> Dictionary:
	var best := {}
	var bd := cells + 1
	for e in player_fleets(st):
		if e.has("busy") or not CState.at_war(st, int(fl["f"]), int(e["f"])):
			continue
		var d := CGrid.cheb(CFleet.cell(fl), CFleet.cell(e))
		if d < bd:
			bd = d
			best = e
	return best


## The end of the turn (CTurn.resolve_turn, after the turn number moved on):
## the pressures, the actors' clocks, a rescue for a captain left with
## nothing, the hunt's contact, then the events.
static func end_turn(st: Dictionary) -> void:
	if not on(st):
		return
	var t := int(st["turn"])
	var pf := player(st)
	# Plunder: the purse, shares owed, Lindo's cut.
	var pl := _plunder(st)
	var delta := pl - int(S(st)["plunder0"])
	if delta > 0:
		S(st)["plunder_t"] = t
		add_p(st, "purse", -mini(delta / int(_c(st, "PURSE_PLUNDER_DIV", 6)), int(_c(st, "PURSE_PLUNDER_MAX", 60))))
		add_p(st, "owed", delta * int(_c(st, "OWED_PCT", 50)) / 100)
		if timer_on(st, "lindo") and pf >= 0:
			var bonus := delta * int(_c(st, "LINDO_PCT", 25)) / 100
			var fs: Dictionary = st["factions"][pf]
			fs["treasury"] = int(fs["treasury"]) + bonus
		S(st)["plunder0"] = _plunder(st)
	else:
		add_p(st, "purse", int(_c(st, "PURSE_TURN", 6)) + (int(_c(st, "PURSE_OWED", 2)) if p(st, "owed") >= int(_c(st, "OWED_HIGH", 300)) else 0))
	add_p(st, "heat", -1)
	# The haven drifts toward what its walls, its garrison and Spain's attention make it.
	var hr := CData.region_index(str(_c(st, "HAVEN", "")))
	if hr >= 0 and captains(st).has(CState.owner(st, hr)):
		var target := int(_c(st, "HAVEN_BASE", 40)) + int(_c(st, "HAVEN_WALL", 15)) * CState.walls(st, hr) \
			- attention(st) / int(_c(st, "HAVEN_ATT_DIV", 4))
		for a in st["armies"]:
			if captains(st).has(int(a["f"])) and CGrid.cheb(CState.cell(a), CGrid.site(hr)) <= 1:
				target += int(_c(st, "HAVEN_ARMY", 15))
				break
		var step := int(_c(st, "HAVEN_STEP", 5))
		add_p(st, "haven", clampi(clampi(target, 0, P_MAX) - p(st, "haven"), -step, step))
	elif hr >= 0:
		add_p(st, "haven", -P_MAX)
	# Timers run out.
	var tl: Array = []
	for tm in S(st)["timers"]:
		if int(tm[1]) > t:
			tl.append(tm)
	S(st)["timers"] = tl
	# Actors: their time runs out, or they are gone (sunk or taken by someone).
	for a in (S(st)["actors"] as Array).duplicate():
		var fl := actor_fleet(st, str(a["k"]))
		if fl.is_empty():
			set_flag(st, "gone_" + str(a["k"]))
			var raw := CFleet.fleet(st, int(a["fl"]))
			if not raw.is_empty() and (raw["ships"] as Array).is_empty() and (raw["carry"] as Array).is_empty():
				(st["fleets"] as Array).erase(raw)
			_drop_actor(st, str(a["k"]))
			continue
		if int(a.get("ttl", 0)) > 0:
			a["ttl"] = int(a["ttl"]) - 1
			if int(a["ttl"]) == 0 and not fl.has("busy"):
				(st["fleets"] as Array).erase(fl)
				set_flag(st, "gone_" + str(a["k"]))
				_drop_actor(st, str(a["k"]))
	_rescue(st)
	_hunt(st)
	check(st)


## A captain with no ship and no land (spared by check_eliminations while
## rescues are left) is fished out of the surf: a battered sloop by the haven.
static func _rescue(st: Dictionary) -> void:
	for f in captains(st):
		var cf := int(f)
		if not CState.alive(st, cf) or not flagship(st, cf).is_empty() or not CState.regions_of(st, cf).is_empty():
			continue
		if int(S(st)["mercy"]) <= 0:
			continue
		S(st)["mercy"] = int(S(st)["mercy"]) - 1
		var hr := CData.region_index(str(_c(st, "HAVEN", "")))
		var c := CFleet.dock(hr) if hr >= 0 else -1
		if c < 0:
			c = _sea_near(_pos_cell(st, _c(st, "LAIR", [0, 0])))
		var fl := CFleet._new_fleet(st, cf, c, [{"t": "sloop", "h": 50, "c": 45}])
		var cap := {}
		for cc in CCaptain.of_faction(st, cf):
			if int(cc["fl"]) < 0:
				cap = cc
				break
		if not cap.is_empty():
			cap["fl"] = int(fl["id"])
		_sched(st, "cast_ashore", int(st["turn"]))


## The hunt for an actor (flag "hunt_<k>"): a captain's fleet within the
## script's HUNT_CELLS of it brings it to battle.
static func _hunt(st: Dictionary) -> void:
	for a in (S(st)["actors"] as Array).duplicate():
		var k := str(a["k"])
		if not flag(st, "hunt_" + k) or flag(st, "won_" + k) or flag(st, "lost_" + k):
			continue
		var en := actor_fleet(st, k)
		if en.is_empty() or en.has("busy"):
			continue
		for fl in player_fleets(st):
			if fl.has("busy") or CGrid.cheb(CFleet.cell(fl), CFleet.cell(en)) > int(_c(st, "HUNT_CELLS", 3)):
				continue
			var before := int(st["next_battle"])
			CFleet.sea_battle(st, fl, [en], CFleet.cell(fl))
			if int(st["next_battle"]) > before:
				(S(st)["bt"] as Array).append([before, k])
			break


# -------------------------------------------------------------- battles ---

## Before pending battle bid is applied (CTurn.apply_battle): what the story
## needs to read its result afterwards ({} not a story campaign).
static func before_battle(st: Dictionary, bid: int) -> Dictionary:
	if not on(st):
		return {}
	var b := CState.battle(st, bid)
	if b.is_empty():
		return {}
	var tags: Array = []
	for bt in S(st)["bt"]:
		if int(bt[0]) == bid:
			tags.append(str(bt[1]))
	var side := -1
	if b.has("sea"):
		for k in 2:
			for id in b["af" if k == 0 else "df"]:
				var fl := CFleet.fleet(st, int(id))
				if fl.is_empty():
					continue
				if fl.has("sto") and not tags.has(str(fl["sto"])):
					tags.append(str(fl["sto"]))
				if captains(st).has(int(fl["f"])):
					side = k
	else:
		var fs: Array = _rules().battle_factions(st, b)
		for k in 2:
			for f in fs[k]:
				if captains(st).has(int(f)):
					side = k
	return {"bid": bid, "tags": tags, "side": side, "sea": 1 if b.has("sea") else 0, "ev": (st["events"] as Array).size()}


## After it: flags won_<tag> / lost_<tag> for the captains' side, a rescue,
## then the events.
static func battle_done(st: Dictionary, info: Dictionary) -> void:
	if info.is_empty() or not on(st):
		return
	var won := -1
	var evs: Array = st["events"]
	for i in range(int(info["ev"]), evs.size()):
		var e: Dictionary = evs[i]
		if int(info["sea"]) != 0 and str(e.get("k", "")) == "sea_battle":
			won = 1 if int(e["won"]) == int(info["side"]) else 0
		elif int(info["sea"]) == 0 and str(e.get("k", "")) == "battle":
			won = 1 if int(e["winner"]) == int(info["side"]) else 0
	var bl: Array = []
	for bt in S(st)["bt"]:
		if int(bt[0]) != int(info["bid"]):
			bl.append(bt)
	S(st)["bt"] = bl
	if won >= 0 and int(info["side"]) >= 0:
		for tg in info["tags"]:
			set_flag(st, ("won_" if won == 1 else "lost_") + str(tg))
	_rescue(st)
	check(st)


# ------------------------------------------------------------------ view ---

## The text of a story event (the view and the chronicle): its title.
static func title_of(st: Dictionary, id: String) -> String:
	return str(event_def(st, id).get("title", id))
