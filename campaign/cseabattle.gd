extends RefCounted
## Sea battles fought in real time (N3a; docs/CAMPAIGN.md "Sea battles
## fought (N3a)", docs/DESIGN.md "Sea battles (as built, N3a)"). A pending
## sea battle (CFleet._pending: a battle record with "sea": 1, "af" / "df"
## fleet ids) becomes a SeaSim scenario here (build), and the sim's result
## an outcome (outcome_from_result) that CFleet.apply_sea writes back into
## the fleets. Pure functions of the state, like cbattle.gd: both clients
## build the same scenario from the same state.
##
## Sim side 0 is always the attackers (af), 1 the defenders (df); the
## human's side is commanded by the player, the other by the battle AI.
## Ships: every ship of every fleet of a side, in fleet order, with its hull
## and crew %, the side's crew quality (the pack's SEA_CREWS by faction:
## gunnery q, boarding bq), troops aboard (the fleet's carried men shared
## over its ships by their places), a captain's fear in morale (his own
## ships + FEAR_PCT, a Feared captain's enemies - SEA_FEAR_FOE), the view's
## extras (faction, name, treasure). The wind is the campaign's (WIND_FROM_DEG,
## WIND_STRENGTH) with a seeded shift of up to SEA_WIND_VAR degrees; the
## water is the battle cell's: a coast on the sides where its neighbours
## are land, else open sea with an island at SEA_ISLAND_PCT %.
##
## N3b / N3c: each ship also carries its crew kit for the deck melee ("ck":
## the faction key, SeaSim.ST.DECK_CREWS), the troops aboard by unit type
## ("tk": the fleet's carried units, the three most numerous, as % of the
## men) and the captain's fighting % ("cq": 100 + CAPT_CQ x his fame tier).
## Live co-op (milestone 5 at sea): "controller" per ship (the human
## faction commanding it: a human's ships their own; an AI ally's ships on a
## side with humans that side's lowest human friendly to it, else its
## lowest; -1 on a side without humans), "battle" and "sim_side" (campaign
## side -> sim side: always [0, 1]) as CBattle.build gives them, for
## game/net/coop_session.gd.

const CData := preload("res://campaign/cdata.gd")
const CState := preload("res://campaign/cstate.gd")
const CGrid := preload("res://campaign/cgrid.gd")
const CFleet := preload("res://campaign/cfleet.gd")
const CCaptain := preload("res://campaign/ccaptain.gd")
const CP := preload("res://campaign/cai_profile.gd")
const SeaSim := preload("res://sim/sea_sim.gd")

const FATE_AFLOAT := 0
const FATE_SUNK := 1
const FATE_TAKEN := 2
const FATE_FLED := 3
const CAPT_CQ := 20       # a captain's fighting % a fame tier (N3b deck melee)


static func is_sea(b: Dictionary) -> bool:
	return int(b.get("sea", 0)) != 0


## The fleets of each side still afloat: [attackers, defenders].
static func sides(st: Dictionary, b: Dictionary) -> Array:
	var out := [[], []]
	for k in 2:
		for id in b["af" if k == 0 else "df"]:
			var fl := CFleet.fleet(st, int(id))
			if not fl.is_empty():
				out[k].append(fl)
	return out


static func seed_of(st: Dictionary, b: Dictionary) -> int:
	var h := int(st["seed"]) * 1000003 + int(b["id"]) * 7919 + int(st["turn"]) * 104729 + 0x5EA
	h = (h ^ (h >> 13)) * 0x5bd1e995
	return (h ^ (h >> 15)) & 0x7FFFFFFF


## The sea battle's scenario. human_f: the faction commanded by the player
## (its side's ships; -1: both sides under the AI).
static func build(st: Dictionary, b: Dictionary, human_f: int = -1) -> Dictionary:
	CData.use_state(st)
	var sd := seed_of(st, b)
	var rs := sd
	var c := CGrid.at(int(b["x"]), int(b["y"]))
	var sdz := sides(st, b)
	var units: Array = []
	var ships: Array = []   # per sim ship: [fleet id, ship index]
	var ufac: Array = []
	var feared := [false, false]
	for k in 2:
		for fl in sdz[k]:
			var cp := CCaptain.of_fleet(st, int(fl["id"]))
			if not cp.is_empty() and CCaptain.tier(int(cp["fame"])) >= 2:
				feared[k] = true
	for k in 2:
		for fl in sdz[k]:
			var f := int(fl["f"])
			var crews: Dictionary = CData.ship_const("SEA_CREWS", {})
			var cq: Array = crews.get(str(CData.FACTIONS[f]["key"]), [100, 100])
			var fear := CCaptain.fear_pct(st, fl)
			var men := _carried_men(fl)
			var tk := troop_kits(fl)
			var cpt := CCaptain.of_fleet(st, int(fl["id"]))
			var capq := 100 + (CAPT_CQ * CCaptain.tier(int(cpt["fame"])) if not cpt.is_empty() else 0)
			var cap := maxi(CFleet.capacity(fl), 1)
			var list: Array = fl["ships"]
			for i in list.size():
				var s: Dictionary = list[i]
				var row := CData.ship_row(str(s["t"]))
				var share := men * int(row.get("cap", 0)) / cap
				var mor := 100 + fear - (int(CData.ship_const("SEA_FEAR_FOE", 15)) if feared[1 - k] else 0)
				var bq0 := 100
				var srow := SeaSim.ST.index_of(str(s["t"]))
				if srow >= 0:
					bq0 = SeaSim.ST.stat(srow, "board")
				var u := {"side": k, "t": str(s["t"]), "hull": clampi(int(s["h"]), 1, 100), "crew": clampi(int(s["c"]), 1, 100),
					"q": int(cq[0]), "bq": bq0 * int(cq[1]) / 100, "troops": share, "mor": mor, "f": f,
					"ck": str(CData.FACTIONS[f]["key"]), "cq": capq}
				if share > 0 and not tk.is_empty():
					u["tk"] = tk.duplicate(true)
				if s.has("nm"):
					u["nm"] = str(s["nm"])
				if int(s.get("g", 0)) > 0:
					u["g"] = int(s["g"])
				units.append(u)
				ships.append([int(fl["id"]), i])
				ufac.append(f)
	rs = (rs * 1103515245 + 12345) & 0x7FFFFFFF
	var var_deg := int(CData.ship_const("SEA_WIND_VAR", 30))
	var wind := int(CData.ship_const("WIND_FROM_DEG", 90)) + (rs % (2 * var_deg + 1)) - var_deg
	rs = (rs * 1103515245 + 12345) & 0x7FFFFFFF
	var wstr := clampi(int(CData.ship_const("WIND_STRENGTH", 80)) + rs % 31 - 15, 30, 100)
	rs = (rs * 1103515245 + 12345) & 0x7FFFFFFF
	var land := land_of(c, rs)
	var hs := human_f
	var ai := [1, 1]
	if hs >= 0:
		for k in 2:
			for fl in sdz[k]:
				if CState.friendly(st, int(fl["f"]), hs) or int(fl["f"]) == hs:
					ai[k] = 0
	var dirs := int(land.get("dirs", 0))
	var lay := "ns"
	if (dirs >> 2) & 1 != 0 or (dirs >> 6) & 1 != 0:
		lay = "we"
	# The battle AI's skill per sim side (the campaign's Battle AI setting, a faction's own when it has one); the
	# player's side keeps the default, which the sim never reads for it.
	var skill := [CP.AVERAGE, CP.AVERAGE]
	for k in 2:
		if ai[k] == 1 and not (sdz[k] as Array).is_empty():
			var lead := int((sdz[k][0] as Dictionary)["f"])
			if not CState.is_human(st, lead):
				skill[k] = CP.battle_skill(st, lead)
	var scn := {"sea": 1, "ai_skill": skill, "width_m": SeaSim.FIELD_W, "height_m": SeaSim.FIELD_H, "wind_deg": (wind + 360) % 360,
		"wind_str": wstr, "ai_sides": ai, "land": land, "layout": lay, "units": units,
		"time_limit": int(CData.ship_const("SEA_TIME_LIMIT", 900))}
	var player_side := 0 if ai[0] == 0 else (1 if ai[1] == 0 else 0)
	return {"sea": 1, "scenario": scn, "seed": sd, "ships": ships, "map": ships, "player_side": player_side,
		"bid": int(b["id"]), "battle": int(b["id"]), "x": int(b["x"]), "y": int(b["y"]), "sim_side": [0, 1],
		"unit_faction": ufac, "controller": controllers(st, units, ufac)}


## The human faction commanding each ship in a live sea battle (CBattle's
## rule): a human's ships their own; another's on a side with humans that
## side's lowest human friendly to it, else its lowest; -1 on a side with no
## human.
static func controllers(st: Dictionary, units: Array, ufac: Array) -> Array:
	var hum := [[], []]
	for u in ufac.size():
		var f := int(ufac[u])
		var k := clampi(int((units[u] as Dictionary)["side"]), 0, 1)
		if CState.is_human(st, f) and not (hum[k] as Array).has(f):
			hum[k].append(f)
	for k in 2:
		(hum[k] as Array).sort()
	var out: Array = []
	for u in ufac.size():
		var f := int(ufac[u])
		var k := clampi(int((units[u] as Dictionary)["side"]), 0, 1)
		if CState.is_human(st, f):
			out.append(f)
			continue
		var c := -1
		if not (hum[k] as Array).is_empty():
			c = int(hum[k][0])
			for h in hum[k]:
				if CState.friendly(st, f, int(h)):
					c = int(h)
					break
		out.append(c)
	return out


## The troops a fleet carries by unit type for the deck melee: the three most
## numerous types (ties: the first carried) as [[unit key, % of the men]].
static func troop_kits(fl: Dictionary) -> Array:
	var keys: Array = []
	var men: Array = []
	var tot := 0
	for a in fl["carry"]:
		for u in a["units"]:
			var t := str(u["t"])
			var n := int(u["n"])
			var i := keys.find(t)
			if i < 0:
				keys.append(t)
				men.append(n)
			else:
				men[i] = int(men[i]) + n
			tot += n
	var out: Array = []
	if tot <= 0:
		return out
	var used := {}
	for k in mini(3, keys.size()):
		var best := -1
		for i in keys.size():
			if used.has(i):
				continue
			if best < 0 or int(men[i]) > int(men[best]):
				best = i
		used[best] = true
		out.append([str(keys[best]), maxi(int(men[best]) * 100 / tot, 1)])
	return out


## The water of a battle at sea cell c: a coast on the sides where the
## neighbouring cells are land (dir bit i: toward sim angle i x 128, 0 east,
## 2 south, 4 west, 6 north), else open sea and (seeded) an island.
static func land_of(c: int, rs: int) -> Dictionary:
	var dirs := 0
	var dxy := [[1, 0], [1, 1], [0, 1], [-1, 1], [-1, 0], [-1, -1], [0, -1], [1, -1]]
	var x := CGrid.cx(c)
	var y := CGrid.cy(c)
	for i in 8:
		var nx := x + int(dxy[i][0])
		var ny := y + int(dxy[i][1])
		if nx < 0 or ny < 0 or nx >= CGrid.width() or ny >= CGrid.height():
			continue
		if not CFleet.is_sea(CGrid.at(nx, ny)):
			dirs |= 1 << i
	if dirs != 0:
		return {"kind": 2, "dirs": dirs, "mseed": rs % 100000}
	var pct := int(CData.ship_const("SEA_ISLAND_PCT", 25))
	if CFleet.coast_dist(c) <= 2:
		pct *= 2
	if (rs >> 8) % 100 < pct:
		return {"kind": 1, "mseed": rs % 100000}
	return {"kind": 0, "mseed": rs % 100000}


static func _carried_men(fl: Dictionary) -> int:
	var n := 0
	for a in fl["carry"]:
		for u in a["units"]:
			n += int(u["n"])
	return n


## The outcome of a fought sea battle from the sim's result(): winner (0
## attackers, 1 defenders), per ship [fleet, index, fate, hull %, crew %],
## per fleet the troops' share left (% of the men carried). forfeit: the
## player left before it was decided: their side loses, its ships still
## fighting get away.
static func outcome_from_result(built: Dictionary, res: Dictionary, mode: String, forfeit_side: int = -1) -> Dictionary:
	var ships: Array = []
	var troops := {}
	var units: Array = res["units"]
	var map: Array = built["ships"]
	var scn_units: Array = built["scenario"]["units"]
	for i in mini(units.size(), map.size()):
		var u: Dictionary = units[i]
		var fate := FATE_AFLOAT
		match int(u["state"]):
			SeaSim.S_SUNK:
				fate = FATE_SUNK
			SeaSim.S_TAKEN:
				fate = FATE_TAKEN
			SeaSim.S_FLED:
				fate = FATE_FLED
		if forfeit_side >= 0 and int(u["side"]) == forfeit_side and int(u["state"]) == SeaSim.S_STRUCK:
			fate = FATE_TAKEN
		var h := clampi(int(u["hull"]) * 100 / maxi(int(u["hull0"]), 1), 0, 100)
		var cr := clampi(int(u["crew"]) * 100 / maxi(int(u["crew0"]), 1), 0, 100)
		ships.append([int(map[i][0]), int(map[i][1]), fate, h, cr, int(u.get("blown", 0)), int(u.get("kills", 0))])
		var fk := str(int(map[i][0]))
		var t0 := int((scn_units[i] as Dictionary).get("troops", 0))
		var t: Array = troops.get(fk, [0, 0])
		t[0] = int(t[0]) + t0
		t[1] = int(t[1]) + (mini(int(u["troops"]), t0) if fate != FATE_TAKEN and fate != FATE_SUNK else 0)
		troops[fk] = t
	var tl: Array = []
	var keys: Array = troops.keys()
	keys.sort_custom(func(a, b): return int(a) < int(b))
	for k in keys:
		var t2: Array = troops[k]
		tl.append([int(k), int(t2[1]) * 100 / maxi(int(t2[0]), 1) if int(t2[0]) > 0 else 100])
	var w := int(res["winner"])
	if forfeit_side >= 0:
		w = 1 - forfeit_side
	if w < 0:
		w = 1
	return {"sea": 1, "mode": mode, "winner": w, "ships": ships, "troops": tl, "ticks": int(res.get("tick", 0))}


## The player left a sea battle that was not decided: the result as it
## stands, their side beaten (its ships still fighting get away).
static func outcome_forfeit(built: Dictionary, res: Dictionary) -> Dictionary:
	return outcome_from_result(built, res, "forfeit", int(built.get("player_side", 0)))


## Auto-resolve: the campaign's formula (CFleet.resolve) when it is applied.
static func formula_outcome() -> Dictionary:
	return {"sea": 1, "mode": "formula", "winner": -1}
