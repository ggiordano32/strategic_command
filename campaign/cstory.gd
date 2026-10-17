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
##     "home" | "blockade"), until (chase, blockade: turn), home (region
##     key), x, y (goal cell), ttl (turns left, 0 none), (step 2) att (hunt:
##     the attention it hunts from), rest (hunt, chase: the turn it hunts
##     again after a battle), at (blockade: the region)}] (the story's fleets:
##     tagged "sto" = k, left out of the AI's fleet plans),
##   bt [[battle id, tag]] (battles the story opened), plunder0 (the
##     captains' plunder seen), plunder_t (turn of the last plunder), mercy
##     (rescues left for a captain with no ship and no land),
##   (step 2, lazy: absent until first written) fp {held (turns the
##     fortified haven was held), gold (the free port's chest)} (the Act 3
##     goal, once revealed), sx {tk (ships taken), sk (towns sacked), bw /
##     bl (battles won / lost)} (the ending's stats), end (the ending's key:
##     "republic" | "pardon" | "legend"), end_t (its turn)}.
## Captains the story made (join) carry "sto" = the actor key they came from.
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
static func new_story(p_name: String, p_seed: int, settings: Dictionary = {}, key: String = "brethren", coop: bool = false) -> Dictionary:
	var sc: GDScript = SCRIPTS[key]
	var m := sc.get_script_constant_map()
	var stt: Dictionary = (m["START"] as Dictionary).get("settings", {}).duplicate()
	for k in settings:
		stt[k] = settings[k]
	CData.use_pack("west")
	var pf := CData.faction_index(str(m["PLAYER"]))
	var humans: Array = [pf]
	var pf2 := -1
	if coop and m.has("PARTNER"):
		pf2 = CData.faction_index(str(m["PARTNER"]))
		if pf2 >= 0:
			humans.append(pf2)
	var st := CState.new_campaign(p_name, p_seed, humans, stt, [], "west")
	_setup(st, key, pf, pf2)
	# (format 8) the fog-of-war memory of the story's start, not the pack's.
	(load("res://campaign/csight.gd") as GDScript).call("update_memory", st)
	return st


static func _setup(st: Dictionary, key: String, pf: int, pf2: int = -1) -> void:
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
	if pf2 >= 0:
		_setup_partner(st, m, pf2)
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


## (Co-op) The second captain: his faction keeps only the script's lands, a
## sloop with a company aboard off Port Royal, a small garrison at home.
static func _setup_partner(st: Dictionary, m: Dictionary, pf2: int) -> void:
	var ps: Dictionary = m["PARTNER_START"]
	(S(st)["cap"] as Array).append(pf2)
	var fs: Dictionary = st["factions"][pf2]
	fs["treasury"] = int(ps.get("treasury", 0))
	fs["infamy"] = int(ps.get("infamy", 0))
	var keep: Array = ps.get("keep_regions", [])
	for r in CData.region_count():
		if CState.owner(st, r) == pf2 and not keep.has(str(CData.REGIONS[r]["key"])):
			st["regions"][r]["owner"] = -1
	var arm: Array = []
	for a in st["armies"]:
		if int(a["f"]) != pf2:
			arm.append(a)
	st["armies"] = arm
	CFleet.drop_faction(st, pf2)
	if st.has("captains"):
		var cs: Array = []
		for c in st["captains"]:
			if int(c["f"]) != pf2:
				cs.append(c)
		st["captains"] = cs
	for k in ps.get("peace", []):
		var g := CData.faction_index(str(k))
		if g >= 0 and CState.dip(st, pf2, g) == CState.WAR:
			CState.set_dip(st, pf2, g, CState.PEACE)
	for r in CData.region_count():
		if CState.owner(st, r) == pf2 and not (ps.get("army", []) as Array).is_empty():
			var na := _new_army(st, pf2, r, ps["army"])
			CState.place(na, CGrid.site(r))
			_rules()._insert_army(st, na)
			break
	var c0 := _sea_near(_pos_cell(st, ps["at"]))
	var fl := CFleet._new_fleet(st, pf2, c0, [_ship((ps["ship"] as Dictionary).duplicate())])
	for u in ps.get("aboard", []):
		var a2 := _new_army(st, pf2, CGrid.region(_land_near(c0)), [str(u[0])], int(u[1]))
		(fl["carry"] as Array).append(a2)
	var cap := CCaptain._new(st, pf2, int(fl["id"]))
	cap["nm"] = str(m.get("PARTNER_CAPTAIN", "The Partner"))
	cap["fame"] = 5


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


## The captain the story speaks to first (-1 none): the lead captain, the
## haven's owner. With two captains (co-op) the first one still alive.
static func player(st: Dictionary) -> int:
	var c := captains(st)
	if c.size() > 1:
		for f in c:
			if CState.alive(st, int(f)):
				return int(f)
	return int(c[0]) if not c.is_empty() else -1


## Co-op (two captains): the captains still alive, in order.
static func voters(st: Dictionary) -> Array:
	var out: Array = []
	for f in captains(st):
		if CState.alive(st, int(f)):
			out.append(int(f))
	return out


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
## A crew vote (an entry with "v") waits for each captain who has not voted
## yet; with f < 0 it is listed while it is open at all.
static func pending_for(st: Dictionary, f: int = -1) -> Array:
	if not on(st):
		return []
	var out: Array = []
	for pe in S(st)["pending"]:
		if f < 0:
			out.append(pe)
		elif pe.has("v"):
			if captains(st).has(f) and vote_of(pe, f) < 0:
				out.append(pe)
		elif int(pe["f"]) == f:
			out.append(pe)
	return out


static func _men(a: Dictionary) -> int:
	var n := 0
	for u in a["units"]:
		n += int(u["n"])
	return n


## A crew vote (co-op): the choice is answered by both captains.
static func is_vote(pe: Dictionary) -> bool:
	return pe.has("v")


## Captain f's answer in vote pe (-1: not voted yet).
static func vote_of(pe: Dictionary, f: int) -> int:
	for v in pe.get("v", []):
		if int(v[0]) == f:
			return int(v[1])
	return -1


## The captains a vote is still waiting for.
static func vote_waiting(st: Dictionary, pe: Dictionary) -> Array:
	var out: Array = []
	for f in voters(st):
		if vote_of(pe, int(f)) < 0:
			out.append(int(f))
	return out


## Mercy's weight of captain f's side in a split vote: 10 a point of fame
## (the most famous captain), 1 for 10 % of a ship's crew, 1 for 10 men
## (aboard or ashore).
static func vote_weight(st: Dictionary, f: int) -> int:
	var w := 10 * CCaptain.best_fame(st, f)
	var men := 0
	for fl in CFleet.fleets_of(st, f):
		for sh in fl["ships"]:
			w += int(sh["c"]) / 10
		for a in fl["carry"]:
			men += _men(a)
	for a in st["armies"]:
		if int(a["f"]) == f:
			men += _men(a)
	return w + men / 10


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
## flagship), or "lair" (the script's LAIR), or a name whose upper case is
## a script constant [lon, lat] ("pinos": PINOS).
static func _pos_cell(st: Dictionary, pos) -> int:
	if pos is String:
		if str(pos) == "lair":
			return _pos_cell(st, _c(st, "LAIR", [0, 0]))
		var r := CData.region_index(str(pos))
		if r < 0:
			var named = _c(st, str(pos).to_upper(), null)  # (a place the script names: PINOS, STRAITS...)
			return _pos_cell(st, named) if named is Array else -1
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
	if w.has("flota") and _flotas(st).is_empty():
		return false
	if w.has("noflota") and not _flotas(st).is_empty():
		return false
	if w.has("blockaded") and not _blockaded(st):
		return false
	if w.has("capt") and story_captain(st, str(w["capt"])).is_empty():
		return false
	if w.has("nocapt") and not story_captain(st, str(w["nocapt"])).is_empty():
		return false
	if w.has("fp") and not fp_met(st, str(w["fp"])):
		return false
	if w.has("fp_ge") and fp_count(st) < int(w["fp_ge"]):
		return false
	if w.has("walls_ge") and CState.walls(st, CData.region_index(str(w["walls_ge"][0]))) < int(w["walls_ge"][1]):
		return false
	if w.has("fame_ge") and CCaptain.best_fame(st, pf) < int(w["fame_ge"]):
		return false
	if w.has("sea_pending") and not _sea_pending(st):
		return false
	if w.has("any"):
		var one := false
		for sub in w["any"]:
			if _cond(st, sub):
				one = true
				break
		if not one:
			return false
	return true


## The treasure fleet's fleets on the map (CSea's flota), by id.
static func _flotas(st: Dictionary) -> Array:
	var out: Array = []
	for fl in CFleet.fleets(st):
		if fl.has("flota") and not (fl["ships"] as Array).is_empty():
			out.append(fl)
	return out


## A port of a captain is blockaded by a foe (as of the last turn's end).
static func _blockaded(st: Dictionary) -> bool:
	for r in CData.region_count():
		var b := int(st["regions"][r].get("bk", -1))
		if b >= 0 and captains(st).has(CState.owner(st, r)):
			return true
	return false


## A sea battle with a captain in it is waiting to be fought.
static func _sea_pending(st: Dictionary) -> bool:
	for b in st["battles"]:
		if not b.has("sea"):
			continue
		for id in b["af"] + b["df"]:
			var fl := CFleet.fleet(st, int(id))
			if not fl.is_empty() and captains(st).has(int(fl["f"])):
				return true
	return false


## The captain of ours the story made from actor k ("sto"), with ships ({} none).
static func story_captain(st: Dictionary, k: String) -> Dictionary:
	for c in st.get("captains", []):
		if str(c.get("sto", "")) == k and captains(st).has(int(c["f"])):
			var fl := CFleet.fleet(st, int(c["fl"]))
			if not fl.is_empty() and not (fl["ships"] as Array).is_empty():
				return c
	return {}


# -------------------------------------------------------------- free port ---

## The Act 3 goal (revealed by the effect "free_port"): {} until then.
static func fp(st: Dictionary) -> Dictionary:
	return S(st).get("fp", {})


## The goal's parts: [[key, met 0/1, value, need, text], ...]: "fort" (the
## haven held fortified FP_HOLD turns: walls FP_WALLS+, ours, not
## blockaded nor besieged), "fleet" (the captains' fleets' power against the
## Armada's), "chest" (gold for recognition: plunder since the reveal and
## what is paid in).
static func fp_parts(st: Dictionary) -> Array:
	var g := fp(st)
	var out: Array = []
	var hr := CData.region_index(str(_c(st, "HAVEN", "")))
	var held := int(g.get("held", 0))
	var need_h := int(_c(st, "FP_HOLD", 5))
	var wl := CState.walls(st, hr) if hr >= 0 else 0
	var need_w := int(_c(st, "FP_WALLS", 2))
	var ours := hr >= 0 and captains(st).has(CState.owner(st, hr))
	var htxt := "Hold a fortified haven: %d of %d turns held (walls %d of %d%s)" % [mini(held, need_h), need_h, wl, need_w,
		"" if ours else "; the haven is lost"]
	out.append(["fort", 1 if held >= need_h else 0, mini(held, need_h), need_h, htxt])
	var mine := 0
	for fl in player_fleets(st):
		mine += CFleet.power(fl)
	var arm := armada_power(st)
	var pct := int(_c(st, "FP_FLEET_PCT", 100))
	var need_p := arm * pct / 100
	out.append(["fleet", 1 if mine >= need_p else 0, mine, need_p,
		"A fleet able to beat the Armada: your power %d against %d" % [mine, need_p]])
	var gold := int(g.get("gold", 0))
	var need_g := int(_c(st, "FP_GOLD", 1500))
	out.append(["chest", 1 if gold >= need_g else 0, mini(gold, need_g), need_g,
		"Enough plunder to buy recognition: %d of %d gold in the chest" % [mini(gold, need_g), need_g]])
	return out


## The Armada's power (its fleet, or the script's FP_ARMADA while it is not at sea).
static func armada_power(st: Dictionary) -> int:
	var afl := actor_fleet(st, "armada")
	return CFleet.power(afl) if not afl.is_empty() else int(_c(st, "FP_ARMADA", 300))


static func fp_met(st: Dictionary, part: String) -> bool:
	if fp(st).is_empty():
		return false
	for pt in fp_parts(st):
		if str(pt[0]) == part:
			return int(pt[1]) == 1
	return false


static func fp_count(st: Dictionary) -> int:
	if fp(st).is_empty():
		return 0
	var n := 0
	for pt in fp_parts(st):
		n += int(pt[1])
	return n


# ---------------------------------------------------------------- endings ---

## The ending reached ("" none yet): "republic", "pardon" or "legend".
static func ending(st: Dictionary) -> String:
	return str(S(st).get("end", "")) if on(st) else ""


## The ending's stats: [plunder, ships taken, towns sacked, fame, battles won, battles lost].
static func end_stats(st: Dictionary) -> Dictionary:
	var sx: Dictionary = S(st).get("sx", {})
	var pf := player(st)
	return {"plunder": _plunder(st), "taken": int(sx.get("tk", 0)), "sacked": int(sx.get("sk", 0)),
		"fame": CCaptain.best_fame(st, pf), "won": int(sx.get("bw", 0)), "lost": int(sx.get("bl", 0)),
		"infamy": CSea.infamy(st, pf)}


## The epilogue's fates: [[speaker, text], ...], one per character (the
## script's FATES: the first entry for a speaker whose "end" lists the
## ending (absent: any) and whose "if" holds).
static func fates(st: Dictionary) -> Array:
	var out: Array = []
	var done := {}
	var e := ending(st)
	for fd in _c(st, "FATES", []):
		var who := str(fd["who"])
		if done.has(who):
			continue
		if fd.has("end") and not (fd["end"] as Array).has(e):
			continue
		if fd.has("if") and not _cond(st, fd["if"]):
			continue
		done[who] = 1
		out.append([who, str(fd["text"])])
	return out


## The story's battles and sacks of the turn `t` (from st.events): the
## ending's stats.
## (Tortuga rule) The regions a story captain's haven shield covers: the
## script's HAVEN and the partner's kept regions (co-op).
static func _havens(st: Dictionary) -> Array:
	var out: Array = [str(_c(st, "HAVEN", ""))]
	for k in (_c(st, "PARTNER_START", {}) as Dictionary).get("keep_regions", []):
		out.append(str(k))
	return out


## The sandbox AI of faction f may not march on, besiege, assault, land
## against or blockade region r: a captain's haven, while f is not provoked
## (see provoked()). The story's own attacks (the reprisal, the Treaty's hunters,
## the finale) are effects and never ask. Off after the Legend ending and for
## England after the Treaty. Read by campaign/cai.gd and cai_fleet.gd (only in a
## story campaign: they check st.has("story") first).
static func shielded(st: Dictionary, f: int, r: int) -> bool:
	if not on(st) or r < 0 or (S(st).has("end") and str(S(st)["end"]) == "legend"):
		return false  # (the Republic and the Pardon leave the haven recognised: the shield stays; the Legend's does not)
	var o := CState.owner(st, r)
	if o < 0 or not captains(st).has(o) or captains(st).has(f):
		return false
	if not _havens(st).has(str(CData.REGIONS[r]["key"])):
		return false
	if flag(st, "treaty") and str(CData.FACTIONS[f]["key"]) == "england":
		return false
	return not provoked(st, f)


## Faction f has been provoked: for the Spanish nations, the captains' attention is
## at the Armada's hunt threshold or more; for any, or a captain sacked or blockaded one of f's ports in
## the last PROVOKE_TURNS (8) turns (recorded by _tally; a blockade still on counts).
static func provoked(st: Dictionary, f: int) -> bool:
	# The captains' attention is Spain's: it provokes the Spanish nations only.
	if (_c(st, "SPANISH", []) as Array).has(str(CData.FACTIONS[f]["key"])) and attention(st) >= int(_c(st, "ARMADA_HUNT_ATT", 35)):
		return true
	var t := int(st["turn"])
	for pv in S(st).get("prov", []):
		if int(pv["f"]) == f and t - int(pv["t"]) < int(_c(st, "PROVOKE_TURNS", 8)):
			return true
	for r in CData.region_count():
		if CState.owner(st, r) == f and captains(st).has(int(st["regions"][r].get("bk", -1))):
			return true
	return false


static func _tally(st: Dictionary, t: int) -> void:
	var sx: Dictionary = S(st).get("sx", {})
	for e in st["events"]:
		if int(e.get("turn", -1)) != t:
			continue
		match str(e.get("k", "")):
			"sea_battle":
				var side := -1
				for k in 2:
					for g in e["att" if k == 0 else "def"]:
						if captains(st).has(int(g)):
							side = k
				if side < 0:
					continue
				var won := int(e["won"]) == side
				sx["bw" if won else "bl"] = int(sx.get("bw" if won else "bl", 0)) + 1
				if won:
					sx["tk"] = int(sx.get("tk", 0)) + int(e.get("taken", 0))
			"battle":
				var side2 := -1
				for k in 2:
					for g in e["att" if k == 0 else "def"]:
						if captains(st).has(int(g)):
							side2 = k
				if side2 < 0:
					continue
				var won2 := int(e["winner"]) == side2
				sx["bw" if won2 else "bl"] = int(sx.get("bw" if won2 else "bl", 0)) + 1
			"sack":
				if captains(st).has(int(e["f"])):
					sx["sk"] = int(sx.get("sk", 0)) + 1
					_provoke(st, int(e.get("from", -1)), t, "sack", int(e.get("r", -1)))
			"blockade":
				if captains(st).has(int(e["f"])):
					_provoke(st, int(e.get("from", -1)), t, "blockade", int(e.get("r", -1)))
	if not sx.is_empty():
		S(st)["sx"] = sx


## Faction f was provoked on turn t (a port sacked or blockaded).
static func _provoke(st: Dictionary, f: int, t: int, why: String = "sack", r: int = -1) -> void:
	if f < 0:
		return
	if not S(st).has("prov"):
		S(st)["prov"] = []
	var pl: Array = S(st)["prov"]
	var first := true
	for pv in pl:
		if int(pv["f"]) == f:
			first = false
			pv["t"] = t
			pv["w"] = why
			pv["r"] = r
			break
	var now := int(st["turn"])
	if first:
		# {f, t (turn), w ("sack" | "blockade"), r (the port), n (1: the cooling-off line is still due)}
		pl.append({"f": f, "t": t, "w": why, "r": r, "n": 1})
		_sched(st, "grudge_" + why, now, f)  # Mercy tells it once per nation
	if why == "sack":
		_punitive(st, f)


## The first sack of a nation's port brings a small punitive landing at the haven
## in 3-5 turns (Mercy warns a turn before): cause and effect, once per nation.
## It keeps clear of the turn-10 reprisal.
static func _punitive(st: Dictionary, f: int) -> void:
	if not S(st).has("pun"):
		S(st)["pun"] = []
	var done: Array = S(st)["pun"]
	if done.has(f) or CState.owner(st, _haven_region(st)) < 0 or not captains(st).has(CState.owner(st, _haven_region(st))):
		return
	done.append(f)
	var now := int(st["turn"])
	var land := now + 3 + CState.rand(st, 3)
	var rts: Array = []
	for sc in S(st)["sched"]:
		if str(sc[1]).begins_with("reprisal"):
			rts.append(int(sc[0]))
	for fr in S(st)["fired"]:
		if str(fr[0]).begins_with("reprisal") and now - int(fr[1]) < 4:
			rts.append(int(fr[1]))
	for rt in rts:
		if abs(land - rt) < 3:
			land = rt + 3
	_sched(st, "punitive_warn", maxi(land - 1, now), f)
	_sched(st, "punitive", land, f)


## The haven region of the story (the script's HAVEN), -1 none.
static func _haven_region(st: Dictionary) -> int:
	return CData.region_index(str(_c(st, "HAVEN", "")))


## The grudges the captains carry: [{f, w ("sack" | "blockade" | "attention"), r (the port, -1), left (turns left, -1 while it lasts)}].
static func grudges(st: Dictionary) -> Array:
	var out: Array = []
	if not on(st):
		return out
	var t := int(st["turn"])
	var lim := int(_c(st, "PROVOKE_TURNS", 8))
	var seen := {}
	for pv in S(st).get("prov", []):
		var left := lim - (t - int(pv["t"]))
		if left > 0:
			out.append({"f": int(pv["f"]), "w": str(pv["w"]), "r": int(pv["r"]), "left": left})
			seen[int(pv["f"])] = true
	for r in CData.region_count():
		var b := int(st["regions"][r].get("bk", -1))
		var o := CState.owner(st, r)
		if o >= 0 and captains(st).has(b) and not seen.has(o):
			out.append({"f": o, "w": "blockade", "r": r, "left": -1})
			seen[o] = true
	if attention(st) >= int(_c(st, "ARMADA_HUNT_ATT", 35)):
		for k in _c(st, "SPANISH", []):
			var sf := CData.faction_index(str(k))
			if sf >= 0 and not seen.has(sf):
				out.append({"f": sf, "w": "attention", "r": -1, "left": -1})
	return out


## The line on a haven's city card ("" for any other region).
static func haven_hint(st: Dictionary, r: int) -> String:
	if not on(st) or not captains(st).has(CState.owner(st, r)) or not _havens(st).has(str(CData.REGIONS[r]["key"])):
		return ""
	var names: Array[String] = []
	for g in grudges(st):
		var nm := CData.faction_name(int(g["f"]))
		if not names.has(nm):
			names.append(nm)
	if names.is_empty():
		return "Shielded: no nation holds a grudge."
	return "At risk: %s." % ", ".join(names)


## The grudges that have cooled: Mercy says so once for the first of each.
static func _cool(st: Dictionary) -> void:
	var t := int(st["turn"])
	var lim := int(_c(st, "PROVOKE_TURNS", 8))
	for pv in S(st).get("prov", []):
		if int(pv["n"]) == 1 and t - int(pv["t"]) >= lim and not provoked(st, int(pv["f"])):
			pv["n"] = 2
			_sched(st, "grudge_cool", t, int(pv["f"]))


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
	if pe.has("v"):
		if not voters(st).has(f):
			return "not yours to answer"
		if vote_of(pe, f) >= 0:
			return "you have voted"
	elif int(pe["f"]) != f:
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
	settle_ready(st)  # (co-op) a vote whose last captain fell
	var t := int(st["turn"])
	for pass_i in 4:
		if S(st).has("end"):
			return  # (the story is over: the sandbox plays on)
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
			if S(st).has("end"):
				return
			if (sc as Array).size() > 2:
				S(st)["ctx"] = int(sc[2])
			_fire(st, i)
			S(st).erase("ctx")
			any = true
		var list := events_of(st)
		for i in list.size():
			if S(st).has("end"):
				return
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
	var cxf := int(S(st).get("ctx", -1))
	if (ev.get("choices", []) as Array).is_empty():
		_log(st, id, -1, {"x": cxf} if cxf >= 0 else {})
		return
	var n := int(S(st)["next"])
	S(st)["next"] = n + 1
	var pend := {"id": n, "e": id, "t": t, "f": pf}
	if cxf >= 0:
		pend["x"] = cxf
	if voters(st).size() > 1:
		pend["v"] = []  # (co-op) the crew votes: each living captain answers
	(S(st)["pending"] as Array).append(pend)


static func _log(st: Dictionary, id: String, c: int, extra: Dictionary = {}) -> void:
	var n := int(S(st)["ln"]) + 1
	S(st)["ln"] = n
	var lg: Array = S(st)["log"]
	var le := {"n": n, "t": int(st["turn"]), "e": id, "c": c}
	for k in ["v", "w", "x"]:  # (x: the nation the event is about; a crew vote: the votes [[captain, choice]] and whose choice carried)
		if extra.has(k):
			le[k] = extra[k]
	lg.append(le)
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
	if pe.has("v"):
		# The crew votes (co-op): the answer waits until every living captain has given theirs.
		(pe["v"] as Array).append([f, k])
		if not vote_waiting(st, pe).is_empty():
			return st
		_settle_vote(st, pe)
		return st
	(S(st)["pending"] as Array).erase(pe)
	var ev := event_def(st, str(pe["e"]))
	var ch: Dictionary = ev["choices"][k]
	_log(st, str(pe["e"]), k)
	_fx(st, f, ch.get("fx", []))
	check(st)
	_after_fx(st)
	return st


## Every living captain has voted on pe: agree, it passes; disagree, Mercy
## calls the vote by weight (vote_weight: fame, crew and men; a tie goes to
## the lead captain) and the loser's crew grumbles (-6 % crew and men). The
## lead captain (the haven's owner, whom the script is written for) takes
## the effects; the other captains share crew, hull, fame and infamy.
static func _settle_vote(st: Dictionary, pe: Dictionary) -> void:
	var vs: Array = []  # [captain, choice] in the captains' order
	for f in captains(st):
		var kk := vote_of(pe, int(f))
		if kk >= 0:
			vs.append([int(f), kk])
	var lead := player(st)
	var k := int((vs[0] as Array)[1])
	var win := int((vs[0] as Array)[0])
	var split := false
	for v in vs:
		if int(v[1]) != k:
			split = true
	if split:
		var best := -1
		for v in vs:
			var w := vote_weight(st, int(v[0]))
			if w > best:
				best = w
				k = int(v[1])
				win = int(v[0])
		set_flag(st, "crew_split")
		for v in vs:
			if int(v[0]) != win:
				_crew(st, int(v[0]), -6)
	elif vs.size() > 1:
		win = lead
	(S(st)["pending"] as Array).erase(pe)
	var ev := event_def(st, str(pe["e"]))
	var ch: Dictionary = ev["choices"][k]
	_log(st, str(pe["e"]), k, {"v": vs, "w": win if split else -1})
	var fx: Array = ch.get("fx", [])
	_fx(st, lead, fx)
	var shared: Array = []
	for e in fx:
		if ["crew", "hull", "fame", "infamy"].has(str((e as Array)[0])):
			shared.append(e)
	for o in voters(st):
		if int(o) != lead and not shared.is_empty():
			_fx(st, int(o), shared)
	check(st)
	_after_fx(st)


## Votes whose captains have all answered (one died meanwhile) are settled.
static func settle_ready(st: Dictionary) -> void:
	if not on(st):
		return
	for pe in (S(st)["pending"] as Array).duplicate():
		if pe.has("v") and not (pe["v"] as Array).is_empty() and vote_waiting(st, pe).is_empty():
			_settle_vote(st, pe)


## The punitive landing of the nation in ctx at the first haven a captain still holds
## (its two line companies from the script's PUNITIVE).
static func _fx_punish(st: Dictionary) -> void:
	var f := int(S(st).get("ctx", -1))
	if f < 0:
		return
	var key := str(CData.FACTIONS[f]["key"])
	var table: Dictionary = _c(st, "PUNITIVE", {})
	var units: Array = table.get(key, ["musketeers", "musketeers"])
	for hk in _havens(st):
		var r := CData.region_index(str(hk))
		if r >= 0 and captains(st).has(CState.owner(st, r)):
			_raid(st, ["raid", key, str(hk), units, "punitive"])
			return


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
##   Step 2: dip2 a b "war" | "peace" (between two other factions) | marque
##   nation (its letter for the captain) | unmarque nation (revoked) | ship
##   key [name] (joins the flagship's fleet) | actor_add actor [ships] |
##   actor_lose actor n (its strongest ships, one always left) | actor_att
##   actor n (the attention it hunts from) | until actor n (its chase ends n
##   turns on) | blockade actor region turns | build region chain level |
##   assault region [units] tag (the captain storms it now) | weaken region
##   pct | slight region n (its walls n levels lower: a gate opened, a
##   bastion blown) | desert actor faction (a story captain of ours turns his coat) |
##   free_port (the Act 3 goal revealed) | fp_gold n (into its chest) |
##   ending key. sea_battle actor [tag] [1: the actor attacks] (tag: the
##   flags' name, else the actor's).
##   A battle opened by sea_battle, raid or assault sets flag "bt_<tag>"
##   (it may not open: someone else's battle is pending there, ...).
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
			"punish":
				_fx_punish(st)
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
				_sea_battle(st, f, str(a[1]), str(a[2]) if a.size() > 2 else "", a.size() > 3 and int(a[3]) != 0)
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
			"dip2":
				var g1 := CData.faction_index(str(a[1]))
				var g2 := CData.faction_index(str(a[2]))
				if g1 >= 0 and g2 >= 0 and g1 != g2 and CState.alive(st, g1) and CState.alive(st, g2):
					if str(a[3]) == "war" and not CState.at_war(st, g1, g2):
						_rules().declare_war(st, g1, g2)
					elif str(a[3]) == "peace" and CState.at_war(st, g1, g2):
						_rules().make_peace(st, g1, g2)
			"marque":
				var mn := CData.faction_index(str(a[1]))
				if mn >= 0 and f >= 0 and CState.alive(st, mn) and not CSea.has_marque(st, mn, f):
					CSea.grant(st, mn, f)
			"unmarque":
				var un := CData.faction_index(str(a[1]))
				if un >= 0 and f >= 0 and CSea.has_marque(st, un, f):
					(st["marques"] as Array).erase(CSea.marque_of(st, un, f))
					_rules().event(st, {"k": "marque_end", "a": un, "b": f, "why": "broken"})
			"ship":
				var sfl := flagship(st, f)
				if not sfl.is_empty() and not CData.ship_row(str(a[1])).is_empty():
					var sd := {"t": str(a[1])}
					if a.size() > 2:
						sd["nm"] = str(a[2])
					(sfl["ships"] as Array).append(_ship(sd))
			"actor_add":
				var xfl := actor_fleet(st, str(a[1]))
				if not xfl.is_empty() and not xfl.has("busy"):
					for sd2 in a[2]:
						(xfl["ships"] as Array).append(_ship(sd2))
			"actor_lose":
				var lfl := actor_fleet(st, str(a[1]))
				if not lfl.is_empty() and not lfl.has("busy"):
					for i in int(a[2]):
						if (lfl["ships"] as Array).size() > 1:
							(lfl["ships"] as Array).remove_at(_strongest(lfl))
			"actor_att":
				var aa := actor(st, str(a[1]))
				if not aa.is_empty():
					aa["att"] = int(a[2])
			"until":
				var au := actor(st, str(a[1]))
				if not au.is_empty():
					au["until"] = int(st["turn"]) + int(a[2])
			"blockade":
				var ab := actor(st, str(a[1]))
				if not ab.is_empty() and CData.region_index(str(a[2])) >= 0:
					ab["mode"] = "blockade"
					ab["at"] = str(a[2])
					ab["until"] = int(st["turn"]) + int(a[3])
			"build":
				_build(st, CData.region_index(str(a[1])), str(a[2]), int(a[3]))
			"assault":
				_assault(st, f, a)
			"weaken":
				_weaken(st, CData.region_index(str(a[1])), int(a[2]))
			"slight":
				var sr := CData.region_index(str(a[1]))
				if sr >= 0:
					var keep: Array = []
					for sl in st["regions"][sr]["slots"]:
						var lv := int(sl[1]) - (int(a[2]) if int(sl[0]) == CData.WALLS else 0)
						if lv > 0:
							keep.append([int(sl[0]), lv])
					st["regions"][sr]["slots"] = keep
			"desert":
				_desert(st, f, a)
			"free_port":
				if not S(st).has("fp"):
					S(st)["fp"] = {"held": 0, "gold": 0}
			"fp_gold":
				if S(st).has("fp"):
					var fpd: Dictionary = S(st)["fp"]
					fpd["gold"] = maxi(int(fpd["gold"]) + int(a[1]), 0)
			"ending":
				_ending(st, str(a[1]))
			_:
				push_warning("story: unknown effect %s" % str(a[0]))


static func _sched(st: Dictionary, id: String, t: int, f: int = -1) -> void:
	var sl: Array = S(st)["sched"]
	var i := 0
	while i < sl.size() and int(sl[i][0]) <= t:
		i += 1
	sl.insert(i, [t, id] if f < 0 else [t, id, f])  # (a third item: the nation it is about, "{nation}" in its lines)


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


## ["spawn", actor, faction, pos, [ships], ttl, mode, home]: a fleet the story moves.
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
	if a.size() > 7:
		en["home"] = str(a[7])
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
	c["sto"] = str(a[1])
	_rules().event(st, {"k": "story", "e": "join_" + str(a[1]), "f": f})


## A sea battle now between captain f's flagship and the actor's fleet (it
## comes alongside if it is not already near); `they`: the actor attacks
## (the captain's side defends: in a port of ours, its guns help).
static func _sea_battle(st: Dictionary, f: int, k: String, tag: String = "", they: bool = false) -> void:
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
	if they:
		CFleet.sea_battle(st, en, [fl], c)
	else:
		CFleet.sea_battle(st, fl, [en], c)
	if int(st["next_battle"]) > before:
		(S(st)["bt"] as Array).append([before, tag if tag != "" else k])
		set_flag(st, "bt_" + (tag if tag != "" else k))


## ["raid", faction, region, [units], tag]: an army of faction lands beside
## the settlement and storms it now (a battle, tagged); with a battle
## already pending there, as soon as that one is over (story "rq", this
## turn only).
static func _raid(st: Dictionary, a: Array) -> void:
	var f := CData.faction_index(str(a[1]))
	var r := CData.region_index(str(a[2]))
	if f < 0 or r < 0 or not CState.alive(st, f) or not CState.at_war(st, f, CState.owner(st, r)):
		return
	if not CState.battle_at(st, r).is_empty():
		# Someone else's battle is pending there: they land when it is over (battle_done), this turn.
		if not S(st).has("rq"):
			S(st)["rq"] = []
		(S(st)["rq"] as Array).append(a.duplicate())
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
	set_flag(st, "bt_" + str(a[4]))
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


## The index of fleet fl's strongest ship (the first on a tie).
static func _strongest(fl: Dictionary) -> int:
	var best := 0
	var bp := -1
	for k in (fl["ships"] as Array).size():
		var pw := CFleet.ship_power(fl["ships"][k])
		if pw > bp:
			bp = pw
			best = k
	return best


## ["build", region, chain key, level]: building chain `key` of region r
## is at least `level` (a story's work, over the slot cap if it must).
static func _build(st: Dictionary, r: int, key: String, level: int) -> void:
	if r < 0:
		return
	var ci := -1
	for i in CData.CHAINS.size():
		if str(CData.CHAINS[i]["key"]) == key:
			ci = i
	if ci < 0:
		return
	level = mini(level, int(CData.CHAINS[ci]["levels"]))
	for sl in st["regions"][r]["slots"]:
		if int(sl[0]) == ci:
			sl[1] = maxi(int(sl[1]), level)
			return
	(st["regions"][r]["slots"] as Array).append([ci, level])


## Free field cells beside settlement r (no army on them), in ring order.
static func _free_ring(st: Dictionary, r: int) -> Array:
	var out: Array = []
	var site := CGrid.site(r)
	for k in 8:
		var c := CState.ring_cell(r, k)
		if c == site or out.has(c) or CFleet.is_sea(c):
			continue
		var free := true
		for x in st["armies"]:
			if CState.cell(x) == c:
				free = false
		if free:
			out.append(c)
	return out


## ["assault", region, [units], tag]: captain f storms region r now (a land
## battle, tagged): the companies `units` (the story's landing party) and
## everyone aboard the captain's fleets within ASSAULT_CELLS of its harbour
## land beside the settlement and go over the wall.
static func _assault(st: Dictionary, f: int, a: Array) -> void:
	var r := CData.region_index(str(a[1]))
	if f < 0 or r < 0:
		return
	var o := CState.owner(st, r)
	if o == f or not CState.battle_at(st, r).is_empty():
		return
	if not CState.at_war(st, f, o):
		_rules().declare_war(st, f, o)  # (a story's assault is an act of war)
	var free := _free_ring(st, r)
	if free.is_empty():
		return
	var lead := {}
	if not (a[2] as Array).is_empty():
		lead = _new_army(st, f, r, a[2])
		CState.place(lead, int(free[0]))
		_rules()._insert_army(st, lead)
		free.remove_at(0)
	var hb := CFleet.harbour(r)
	if hb < 0:
		hb = CGrid.site(r)
	for fl in CFleet.fleets_of(st, f):
		if fl.has("busy") or CGrid.cheb(CFleet.cell(fl), hb) > int(_c(st, "ASSAULT_CELLS", 5)):
			continue
		while not (fl["carry"] as Array).is_empty() and not free.is_empty():
			var ca: Dictionary = fl["carry"][0]
			CFleet.land(st, fl, int(free[0]), int(ca["id"]))
			if lead.is_empty():
				lead = ca
			free.remove_at(0)
	if lead.is_empty():
		return
	var b: Dictionary = _rules()._assault6(st, r, lead)
	if b.is_empty():
		return
	_rules().add_reinforcements(st, b)
	b.erase("new")
	(S(st)["bt"] as Array).append([int(b["id"]), str(a[3])])
	set_flag(st, "bt_" + str(a[3]))
	_rules().event(st, {"k": "story", "e": "assault", "f": f, "r": r})


## ["weaken", region, pct]: the defenders of region r (its owner's armies
## by the settlement and its garrison) lose pct % of their men (a bribed
## gate, a fever, a mutiny in the fort).
static func _weaken(st: Dictionary, r: int, pct: int) -> void:
	if r < 0:
		return
	var o := CState.owner(st, r)
	for x in st["armies"]:
		if int(x["f"]) != o or o < 0 or CGrid.cheb(CState.cell(x), CGrid.site(r)) > 1:
			continue
		for u in x["units"]:
			u["n"] = maxi(1, int(u["n"]) * (100 - pct) / 100)
	var rs: Dictionary = st["regions"][r]
	rs["gar"] = int(rs["gar"]) * (100 - pct) / 100


## ["desert", actor, faction]: the captain of ours the story made from
## actor k ("sto") turns his coat: his fleet (and whoever is aboard) sails
## for `faction` as the story's actor k again, holding where it is.
static func _desert(st: Dictionary, f: int, a: Array) -> void:
	var k := str(a[1])
	var c := story_captain(st, k)
	var g := CData.faction_index(str(a[2]))
	if c.is_empty() or g < 0 or not CState.alive(st, g):
		return
	var fl := CFleet.fleet(st, int(c["fl"]))
	if fl.has("busy"):
		return
	fl["f"] = g
	fl["sto"] = k
	fl["carry"] = []
	CFleet._drop_voyage(fl)
	(st["captains"] as Array).erase(c)
	_drop_actor(st, k)
	(S(st)["actors"] as Array).append({"k": k, "fl": int(fl["id"]), "mode": "hold", "ttl": 0})
	(S(st)["flags"] as Array).erase("gone_" + k)
	_rules().event(st, {"k": "story", "e": "desert_" + k, "f": f})


## ["ending", key]: the story ends ("republic", "pardon" or "legend"): its
## stats are counted, the story's fleets go back to their factions' AI and
## no more events fire; the campaign plays on as a sandbox.
static func _ending(st: Dictionary, k: String) -> void:
	if S(st).has("end"):
		return
	S(st)["end"] = k
	S(st)["end_t"] = int(st["turn"])
	set_flag(st, "ended")
	set_flag(st, "end_" + k)
	_tally(st, int(st["turn"]))
	for ac in (S(st)["actors"] as Array).duplicate():
		_release(st, str(ac["k"]))
	S(st)["pending"] = []
	S(st)["sched"] = []
	_rules().event(st, {"k": "story", "e": "end_" + k, "f": player(st)})


## The campaign is over (every captain gone, or a victory): the story's
## ending, if it had none (the script's END_OVER event, else "legend").
static func _over(st: Dictionary) -> void:
	if S(st).has("end"):
		return
	var won := false
	for f in captains(st):
		if int(st.get("winner", -1)) == int(f):
			won = true
	var id := str(_c(st, "END_WON" if won else "END_OVER", ""))
	var i := _event_index(st, id)
	if i >= 0:
		_fire(st, i)
	if not S(st).has("end"):
		_ending(st, "republic" if won else "legend")


# ---------------------------------------------------------- the turn hooks ---

## Step 5 of the turn (CTurn.resolve_turn, with the AI's voyages): the
## story's fleets sail by their modes. chase: the nearest captain's fleet
## (until a turn, then home); hunt (the Armada): a captain's fleet in reach
## while the attention is high, else home; goal: a cell, then hold; home:
## its home port, then back to its faction's AI; blockade: lie off a port of
## ours until a turn, then hunt.
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
				var tg := _nearest_foe(st, fl, 1 << 20) if t >= int(a.get("rest", 0)) else {}
				if not tg.is_empty():
					fmoves.append([int(fl["id"]), -1, f, 0, int(tg["id"])])
			"hunt":
				var att := attention(st)
				var tg2 := {}
				if att >= int(a.get("att", _c(st, "ARMADA_HUNT_ATT", 35))) and t >= int(a.get("rest", 0)):
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
			"blockade":
				var br := CData.region_index(str(a.get("at", "")))
				var bc := CFleet.harbour(br) if br >= 0 else -1
				if bc < 0 or t > int(a.get("until", 0)) or not CState.at_war(st, f, CState.owner(st, br)):
					a["mode"] = "hunt"
				elif CGrid.cheb(CFleet.cell(fl), bc) > 1:
					fmoves.append([int(fl["id"]), _sea_near(bc), f, 0, -1])
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
	if str(st["phase"]) == "over":
		if not S(st).has("end"):
			_tally(st, int(st["turn"]) - 1)
		_over(st)
		return
	if S(st).has("end"):
		return  # (the story has ended: the sandbox plays on)
	var t := int(st["turn"])
	var pf := player(st)
	_tally(st, t - 1)
	S(st).erase("rq")  # (raids that never found the beach clear)
	_cool(st)
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
		if S(st).has("fp"):
			var fpd: Dictionary = S(st)["fp"]
			fpd["gold"] = int(fpd["gold"]) + delta  # (the free port's chest: plunder since the goal was revealed)
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
	# The free port: the turns the fortified haven was held (lost: from nothing again).
	if S(st).has("fp") and hr >= 0:
		var fpd2: Dictionary = S(st)["fp"]
		if not captains(st).has(CState.owner(st, hr)):
			fpd2["held"] = 0
		elif CState.walls(st, hr) >= int(_c(st, "FP_WALLS", 2)) and int(st["regions"][hr].get("bk", -1)) < 0 \
				and CState.siege_at(st, hr).is_empty():
			fpd2["held"] = int(fpd2["held"]) + 1
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
## script's HUNT_CELLS of it brings it to battle (the flota: "hunt_flota").
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
	# (step 2) The flota hunted (flag "hunt_flota"): the same, tagged "flota".
	if flag(st, "hunt_flota") and not flag(st, "won_flota") and not flag(st, "lost_flota"):
		for en in _flotas(st):
			if en.has("busy"):
				continue
			var hit := false
			for fl in player_fleets(st):
				if fl.has("busy") or CGrid.cheb(CFleet.cell(fl), CFleet.cell(en)) > int(_c(st, "HUNT_CELLS", 3)) \
						or not CState.at_war(st, int(fl["f"]), int(en["f"])):
					continue
				var before2 := int(st["next_battle"])
				CFleet.sea_battle(st, fl, [en], CFleet.cell(fl))
				if int(st["next_battle"]) > before2:
					(S(st)["bt"] as Array).append([before2, "flota"])
				hit = true
				break
			if hit:
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
				if fl.has("flota") and not tags.has("flota"):
					tags.append("flota")
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
			var ac := actor(st, str(tg))
			if not ac.is_empty() and (str(ac["mode"]) == "hunt" or str(ac["mode"]) == "chase"):
				ac["rest"] = int(st["turn"]) + int(_c(st, "ACTOR_REST", 3))  # (it refits: hunt goes home, chase lies to)
	if str(st["phase"]) == "over":
		_over(st)
		return
	if S(st).has("rq"):
		var rq: Array = S(st)["rq"]
		S(st).erase("rq")
		for ra in rq:
			_raid(st, ra)
	_rescue(st)
	check(st)
	_after_fx(st)


# ------------------------------------------------------------------ view ---

## The text of a story event (the view and the chronicle): its title.
static func title_of(st: Dictionary, id: String) -> String:
	return str(event_def(st, id).get("title", id))
