extends RefCounted
## Notorious captains (N2b, pirate fleets in a pack with ships; docs/
## CAMPAIGN.md "Hurricanes, captains and named galleons (N2b)"). A pirate
## fleet sails under a named captain who builds fame with prizes, sacks and
## battles won; fame gives perks by tier (cheaper haven crews, a Legend's
## extra recruits, fear in a sea battle, foes striking their colours
## sooner). His fleet destroyed, he is killed, captured (hanged, or
## ransomed when his faction can pay) or escapes ashore to take another
## fleet; the nations pay a bounty for a famous one. Same discipline as the
## rest of campaign/: integers, the state's RNG, arrays in index order.
##
## State (optional, only in a pack with ships): captains [{id, f, nm, fame,
## fl (fleet id, -1 ashore), born (turn), pz (prizes), sk (sacks)}] sorted
## by id; next_capt; stats captains, capt_killed, capt_hanged,
## capt_ransomed, capt_drowned, capt_escaped, max_fame, bounties.

const CData := preload("res://campaign/cdata.gd")
const CState := preload("res://campaign/cstate.gd")
const CGrid := preload("res://campaign/cgrid.gd")
const CFleet := preload("res://campaign/cfleet.gd")


static func _rules() -> GDScript:
	return load("res://campaign/crules.gd")


static func _csea() -> GDScript:
	return load("res://campaign/csea.gd")


static func k(key: String, default: int) -> int:
	return int(CData.ship_const(key, default))


static func pack_on() -> bool:
	return not (CData.ship_const("CAPTAIN_NAMES", []) as Array).is_empty()


static func all(st: Dictionary) -> Array:
	return st.get("captains", [])


static func _stat(st: Dictionary, key: String, n: int) -> void:
	var s: Dictionary = st["stats"]
	s[key] = int(s.get(key, 0)) + n


## The captain of fleet id ({} none).
static func of_fleet(st: Dictionary, fid: int) -> Dictionary:
	for c in all(st):
		if int(c["fl"]) == fid:
			return c
	return {}


static func of_faction(st: Dictionary, f: int) -> Array:
	var out: Array = []
	for c in all(st):
		if int(c["f"]) == f:
			out.append(c)
	return out


## Fame tier: 0 none, 1 Known, 2 Feared, 3 Legend.
static func tier(fame: int) -> int:
	var t := 0
	for v in CData.ship_const("FAME_TIERS", [20, 45, 75]):
		if fame >= int(v):
			t += 1
	return t


static func tier_name(fame: int) -> String:
	var names: Array = CData.ship_const("FAME_TIER_NAMES", ["", "Known", "Feared", "Legend"])
	return str(names[mini(tier(fame), names.size() - 1)])


## The fame of faction f's most famous captain (0 none).
static func best_fame(st: Dictionary, f: int) -> int:
	var b := 0
	for c in all(st):
		if int(c["f"]) == f:
			b = maxi(b, int(c["fame"]))
	return b


## Percent more power fleet fl brings to a sea battle (its captain's fear).
static func fear_pct(st: Dictionary, fl: Dictionary) -> int:
	if not st.has("captains"):
		return 0
	var c := of_fleet(st, int(fl["id"]))
	if c.is_empty():
		return 0
	var fp: Array = CData.ship_const("FEAR_PCT", [0, 5, 10, 20])
	return int(fp[mini(tier(int(c["fame"])), fp.size() - 1)])


## The most famous captain among fleets `side` ({} none).
static func top_of(st: Dictionary, side: Array) -> Dictionary:
	var best := {}
	if not st.has("captains"):
		return best
	for fl in side:
		var c := of_fleet(st, int(fl["id"]))
		if not c.is_empty() and (best.is_empty() or int(c["fame"]) > int(best["fame"])):
			best = c
	return best


## The bounty the nations pay for captain c (0: not famous enough).
static func bounty(c: Dictionary) -> int:
	var fame := int(c["fame"])
	return fame * k("BOUNTY_PER", 12) if fame >= k("BOUNTY_FAME", 25) else 0


# ---------------------------------------------------------------- rising ---

## End of turn (CSea.after_turn): captains whose fleet is gone go ashore
## (the dead faction's are gone); every pirate fleet without a captain
## takes one of its faction's ashore, else a new one rises at CAPT_RISE_PCT
## (at the start: always). Event "captain_rise" (chronicle).
static func rise(st: Dictionary, start: bool = false) -> void:
	if not pack_on() or not st.has("fleets"):
		return
	var csea := _csea()
	var keep: Array = []
	for c in all(st):
		if not CState.alive(st, int(c["f"])):
			continue
		if int(c["fl"]) >= 0 and CFleet.fleet(st, int(c["fl"])).is_empty():
			c["fl"] = -1
		keep.append(c)
	if st.has("captains") or start:
		st["captains"] = keep
	for f in CState.nf():
		if not csea.pirate(f) or not CState.alive(st, f):
			continue
		for fl in CFleet.fleets_of(st, f):
			if (fl["ships"] as Array).is_empty() or csea.is_flota(fl) or not of_fleet(st, int(fl["id"])).is_empty():
				continue
			var ashore := {}
			for c in of_faction(st, f):
				if int(c["fl"]) < 0:
					ashore = c
					break
			if not ashore.is_empty():
				ashore["fl"] = int(fl["id"])
				continue
			if of_faction(st, f).size() >= k("CAPT_MAX", 4):
				break
			if not start and CState.rand(st, 100) >= k("CAPT_RISE_PCT", 35):
				continue
			var c := _new(st, f, int(fl["id"]))
			if not start:
				_rules().event(st, {"k": "captain_rise", "f": f, "nm": str(c["nm"]), "fleet": int(fl["id"]),
					"x": int(fl["x"]), "y": int(fl["y"])})


static func _new(st: Dictionary, f: int, fid: int) -> Dictionary:
	var names: Array = CData.ship_const("CAPTAIN_NAMES", [])
	var used := {}
	for c in all(st):
		used[str(c["nm"])] = 1
	var free: Array = []
	for n in names:
		if not used.has(str(n)):
			free.append(str(n))
	var nm := str(free[CState.rand(st, free.size())]) if not free.is_empty() else "Captain %d" % int(st.get("next_capt", 1))
	var c := {"id": int(st.get("next_capt", 1)), "f": f, "nm": nm, "fame": 0, "fl": fid, "born": int(st["turn"]), "pz": 0, "sk": 0}
	st["next_capt"] = int(c["id"]) + 1
	if not st.has("captains"):
		st["captains"] = []
	(st["captains"] as Array).append(c)
	_stat(st, "captains", 1)
	return c


# ------------------------------------------------------------------ fame ---

## Captain c gains n fame (event "captain_fame" on reaching a tier, chronicle).
static func add_fame(st: Dictionary, c: Dictionary, n: int) -> void:
	if c.is_empty() or n <= 0:
		return
	var old := int(c["fame"])
	c["fame"] = mini(old + n, k("FAME_MAX", 100))
	var s: Dictionary = st["stats"]
	s["max_fame"] = maxi(int(s.get("max_fame", 0)), int(c["fame"]))
	if tier(int(c["fame"])) > tier(old):
		_rules().event(st, {"k": "captain_fame", "f": int(c["f"]), "nm": str(c["nm"]), "fame": int(c["fame"]),
			"tier": tier(int(c["fame"]))})


## A sea battle is over (CFleet.resolve): the winners' captains gain fame
## (the one whose fleet takes the prizes, or the most famous, for the
## prizes and treasure); captains of fleets destroyed meet their fate.
static func after_battle(st: Dictionary, win: Array, lose: Array, gone: Array, prizes: int, treasure: int, c: int) -> void:
	if not st.has("captains"):
		return
	for fl in win:
		if not gone.has(fl):
			add_fame(st, of_fleet(st, int(fl["id"])), k("FAME_WIN", 3))
	if prizes > 0 and not win.is_empty():
		var pc := of_fleet(st, int(win[0]["id"]))
		if pc.is_empty():
			pc = top_of(st, win)
		if not pc.is_empty():
			pc["pz"] = int(pc["pz"]) + prizes
			add_fame(st, pc, prizes * k("FAME_PRIZE", 4) + treasure * k("FAME_TREASURE", 15))
	var wf := int(win[0]["f"]) if not win.is_empty() else -1
	var lf := int(lose[0]["f"]) if not lose.is_empty() else -1
	for fl in gone:
		fleet_lost(st, fl, "battle", lf if win.has(fl) else wf, c)


## Pirate faction f sacked region r: the captain of its fleet nearest the
## harbour (within 4), else its most famous, gains fame.
static func sacked(st: Dictionary, f: int, r: int) -> void:
	if not st.has("captains"):
		return
	var hb := CFleet.harbour(r)
	var best := {}
	var bd := 1 << 30
	for fl in CFleet.fleets_of(st, f):
		var c := of_fleet(st, int(fl["id"]))
		var d := CGrid.cheb(CFleet.cell(fl), hb) if hb >= 0 else 99
		if not c.is_empty() and d <= 4 and d < bd:
			bd = d
			best = c
	if best.is_empty():
		for c in of_faction(st, f):
			if best.is_empty() or int(c["fame"]) > int(best["fame"]):
				best = c
	if not best.is_empty():
		best["sk"] = int(best["sk"]) + 1
		add_fame(st, best, k("FAME_SACK", 10))


## Fleet `from` joins fleet `into`: its captain takes command when the
## other has none or is less famous (the other goes ashore).
static func merged(st: Dictionary, from: int, into: int) -> void:
	if not st.has("captains"):
		return
	var a := of_fleet(st, from)
	if a.is_empty():
		return
	var b := of_fleet(st, into)
	if b.is_empty() or int(a["fame"]) > int(b["fame"]):
		a["fl"] = into
		if not b.is_empty():
			b["fl"] = -1
	else:
		a["fl"] = -1


# ----------------------------------------------------------------- fates ---

## Fleet fl is gone (why "battle" by faction `by`, or "storm") at cell c:
## its captain is killed, drowned, captured (hanged or ransomed) or escapes
## ashore; a bounty for a famous one killed or taken (event "captain_fate",
## chronicle).
static func fleet_lost(st: Dictionary, fl: Dictionary, why: String, by: int, c: int) -> void:
	if not st.has("captains"):
		return
	var cp := of_fleet(st, int(fl["id"]))
	if cp.is_empty():
		return
	var f := int(cp["f"])
	var how := "escaped"
	var roll := CState.rand(st, 100)
	if why == "storm":
		how = "drowned" if roll < k("CAPT_DROWN_PCT", 65) else "escaped"
	elif roll < k("CAPT_KILLED_PCT", 40):
		how = "killed"
	elif roll < k("CAPT_KILLED_PCT", 40) + k("CAPT_CAPTURED_PCT", 45) and by >= 0:
		how = "hanged"
		var ransom := k("RANSOM_BASE", 150) + k("RANSOM_FAME", 10) * int(cp["fame"])
		if int(cp["fame"]) < k("HANG_FAME", 40) and CState.rand(st, 2) == 0 and int(st["factions"][f]["treasury"]) >= ransom:
			how = "ransomed"
	var ev := {"k": "captain_fate", "f": f, "nm": str(cp["nm"]), "fame": int(cp["fame"]), "how": how, "by": by,
		"x": CGrid.cx(c), "y": CGrid.cy(c)}
	var pay := bounty(cp)
	if how in ["killed", "hanged"] and by >= 0 and not _csea().pirate(by) and pay > 0 and CState.alive(st, by):
		st["factions"][by]["treasury"] = int(st["factions"][by]["treasury"]) + pay
		ev["bounty"] = pay
		_stat(st, "bounties", pay)
	match how:
		"hanged":
			ev["r"] = gallows(st, by)
			_stat(st, "capt_hanged", 1)
		"ransomed":
			var ransom2 := k("RANSOM_BASE", 150) + k("RANSOM_FAME", 10) * int(cp["fame"])
			st["factions"][f]["treasury"] = int(st["factions"][f]["treasury"]) - ransom2
			st["factions"][by]["treasury"] = int(st["factions"][by]["treasury"]) + ransom2
			ev["gold"] = ransom2
			_stat(st, "capt_ransomed", 1)
		"killed":
			_stat(st, "capt_killed", 1)
		"drowned":
			_stat(st, "capt_drowned", 1)
		_:
			_stat(st, "capt_escaped", 1)
	if how in ["escaped", "ransomed"]:
		cp["fl"] = -1
	else:
		(st["captains"] as Array).erase(cp)
	_rules().event(st, ev)


## Where faction `by` hangs its pirates: Port Royal (HANG_PORT) when it or
## a friend holds it, else its capital if held, else its first region (-1).
static func gallows(st: Dictionary, by: int) -> int:
	var pr := CData.region_index(str(CData.ship_const("HANG_PORT", "")))
	if pr >= 0 and CState.owner(st, pr) >= 0 and CState.friendly(st, by, CState.owner(st, pr)):
		return pr
	var cap := CData.region_index(str(CData.FACTIONS[by].get("capital", "")))
	if cap >= 0 and CState.owner(st, cap) == by:
		return cap
	var rs := CState.regions_of(st, by)
	return int(rs[0]) if not rs.is_empty() else -1
