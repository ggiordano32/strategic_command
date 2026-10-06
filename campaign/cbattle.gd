extends RefCounted
## Campaign battles <-> the battle sim.
##
## build(): a pending battle as a BattleSim scenario: both sides' armies at
## their current headcounts and tiers, the garrison on the defending side,
## reinforcing armies simply as more units in the line (a simplification:
## later they should arrive from the map edge they come from). A battle at a
## settlement (every battle under the current campaign rules) is fought on
## the settlement's own map (sim/mapgen.gd): from its fixed city_seed, level,
## wall level, buildings, the region's terrain kind, ground palette and
## woods, so a city always looks the same at a given stage; the garrison's
## missile troops start on the walls (Scenarios.settlement). A field battle
## (settlement 0) gets the region's terrain and woods with a seed from
## campaign seed + region + turn. The human side (if any) is sim side 0, at
## the bottom.
##
## Command seam: "unit_faction" lists the campaign faction of every sim
## unit and "controller" the faction that commands it. For now the human
## present commands every unit of the player side (allied armies included);
## co-op battles (milestone 5) will split this per player.
##
## outcome_from_result(): BattleSim.result() mapped back onto campaign units
## (crules.gd apply_outcome input).
##
## formula(): battles between AI factions only, without the sim: side
## strengths from men x value per man (unit price / size), modified for the
## garrison's walls and the defender's ground; attacker wins with probability
## Sa^3 / (Sa^3 + Sd^3) (calibrated against AI-vs-AI sim battles, see
## tests/campaign_battles.gd); losses from the strength ratio.

const CData := preload("res://campaign/cdata.gd")
const CState := preload("res://campaign/cstate.gd")
const CRules := preload("res://campaign/crules.gd")
const UT := preload("res://sim/unit_types.gd")
const Scenarios := preload("res://sim/scenarios.gd")
const Terrain := preload("res://sim/terrain.gd")

const FRONT := 100       # m from the centre line to each side's front
const SECOND_LINE := 45  # m behind the first
const SCREEN := 15       # missile screen ahead of the line
const MAX_LINE := 12     # units in the first line before a second line forms


## Seeds for region r's battle on turn t (battle and terrain).
static func battle_seed(st: Dictionary, r: int, salt: int = 0) -> int:
	var h := int(st["seed"]) * 1000003 + r * 7919 + int(st["turn"]) * 104729 + salt * 15485863
	h = (h ^ (h >> 13)) * 0x5bd1e995
	return (h ^ (h >> 15)) & 0x7FFFFFFF


## Scenario for pending battle b. human_f: faction whose side is sim side 0
## and player-controlled (-1: both sides AI, auto-resolve).
static func build(st: Dictionary, b: Dictionary, human_f: int = -1, scale_pct: int = 100) -> Dictionary:
	var r := int(b["r"])
	var arm := CRules.battle_armies(st, b)
	var gar := CRules.garrison(st, r)
	# Campaign side (0 attackers, 1 defenders) -> sim side.
	var def_on_0 := human_f >= 0 and _side_has(st, arm[1], int(b["def_f"]), human_f)
	var sim_side := [1, 0] if def_on_0 else [0, 1]
	var entries := [[], []]  # per campaign side: {army, unit, t, n, f}
	for s in 2:
		var field := 0
		for a in arm[s]:
			for k in CState.unit_count(a):
				var u: Dictionary = a["units"][k]
				if int(u["n"]) <= 0 or field >= CData.BATTLE_SIDE_MAX:
					continue
				field += 1
				entries[s].append({"army": int(a["id"]), "unit": k, "t": str(u["t"]), "n": int(u["n"]), "f": int(a["f"])})
	for k in gar.size():
		var g: Dictionary = gar[k]
		if int(g["n"]) > 0:
			entries[1].append({"army": -1, "unit": k, "t": str(g["t"]), "n": int(g["n"]), "f": int(b["def_f"])})
	if int(b.get("settlement", 1)) != 0:
		return _build_settlement(st, b, human_f, scale_pct, entries, sim_side, gar)
	var layouts := [_layout(entries[0]), _layout(entries[1])]
	var width := 560
	for s in 2:
		width = maxi(width, int(layouts[s]["width"]) + 160)
	width = mini(width, 960)
	width -= width % 4
	var two_lines := int(layouts[0]["lines"]) > 1 or int(layouts[1]["lines"]) > 1
	var height := 640 if two_lines else 560
	var units: Array = []
	var map: Array = []
	var ufac: Array = []
	for cs in 2:
		var ss: int = sim_side[cs]
		for p in layouts[cs]["placed"]:
			var e: Dictionary = p["e"]
			var ty := UT.index_of(str(e["t"]))
			var x := width / 2 + int(p["x"])
			var y := height / 2 + FRONT + int(p["back"])
			var face := Scenarios.FACE_UP
			if ss == 1:
				x = width - x
				y = height - y
				face = Scenarios.FACE_DOWN
			var cnt := int(e["n"])
			if scale_pct != 100:
				cnt = maxi(cnt * scale_pct / 100, mini(cnt, 8))
				if UT.cls(ty) == UT.CLS_ART:
					cnt = int(e["n"])  # engines and crews are not scaled
			units.append(Scenarios.unit(ss, ty, cnt, x, y, face))
			map.append({"side": cs, "army": int(e["army"]), "unit": int(e["unit"]), "n": int(e["n"]), "sim_n": cnt})
			ufac.append(int(e["f"]))
	var terrain := {"kind": int(CData.REGIONS[r]["terrain"]), "seed": battle_seed(st, r, 1),
		"forest": int(CData.REGIONS[r]["forest"]), "ground": int(CData.REGIONS[r]["ground"])}
	var ai: Array = [0, 1] if human_f < 0 else [1]
	var controller: Array = []
	for f in ufac:
		controller.append(human_f if human_f >= 0 and CState.friendly(st, int(f), human_f) else -1)
	return {"scenario": {"width_m": width, "height_m": height, "ai_sides": ai, "units": units, "terrain": terrain},
		"seed": battle_seed(st, r, 2), "map": map, "sim_side": sim_side, "garrison": gar,
		"unit_faction": ufac, "controller": controller, "battle": int(b["id"]), "region": r}


## Settlement battle: the city's map, attackers before its main gate, the
## defenders (garrison and armies) inside (Scenarios.settlement).
static func _build_settlement(st: Dictionary, b: Dictionary, human_f: int, scale_pct: int,
		entries: Array, sim_side: Array, gar: Array) -> Dictionary:
	var r := int(b["r"])
	var lists := [[], []]
	for cs in 2:
		for e in entries[cs]:
			var ty := UT.index_of(str(e["t"]))
			var cnt := int(e["n"])
			if scale_pct != 100 and UT.cls(ty) != UT.CLS_ART:
				cnt = maxi(cnt * scale_pct / 100, mini(cnt, 8))
			lists[cs].append([ty, cnt])
	var rd: Dictionary = CData.REGIONS[r]
	var cseed := CState.city_seed(st, r)
	var city := {"seed": cseed, "level": int(st["regions"][r]["level"]), "walls": CState.walls(st, r),
		"bld": city_buildings(st, r)}
	var terr := {"kind": int(rd["terrain"]), "seed": (cseed ^ 0x2545F491) & 0x7FFFFFFF,
		"forest": int(rd["forest"]), "ground": int(rd["ground"])}
	var ai: Array = [0, 1] if human_f < 0 else [1]
	var res := Scenarios.settlement(city, terr, lists[0], lists[1], int(sim_side[1]), ai)
	var map: Array = []
	var ufac: Array = []
	for o in res["order"]:
		var cs: int = o[0]
		var e: Dictionary = entries[cs][int(o[1])]
		map.append({"side": cs, "army": int(e["army"]), "unit": int(e["unit"]), "n": int(e["n"]),
			"sim_n": int(lists[cs][int(o[1])][1])})
		ufac.append(int(e["f"]))
	var controller: Array = []
	for f in ufac:
		controller.append(human_f if human_f >= 0 and CState.friendly(st, int(f), human_f) else -1)
	return {"scenario": res["scenario"], "seed": battle_seed(st, r, 2), "map": map, "sim_side": sim_side,
		"garrison": gar, "unit_faction": ufac, "controller": controller, "battle": int(b["id"]), "region": r}


## Building chains standing in region r (sorted; the city map shows them).
static func city_buildings(st: Dictionary, r: int) -> Array:
	var out: Array = []
	for sl in st["regions"][r]["slots"]:
		if int(sl[1]) > 0:
			out.append(int(sl[0]))
	out.sort()
	return out


## Scenario terrain + city for a preview of settlement r's battle map as it
## stands (the region panel's "View battle map"), defenders at the top.
static func city_preview_terrain(st: Dictionary, r: int) -> Dictionary:
	var rd: Dictionary = CData.REGIONS[r]
	var cseed := CState.city_seed(st, r)
	return {"kind": int(rd["terrain"]), "seed": (cseed ^ 0x2545F491) & 0x7FFFFFFF,
		"forest": int(rd["forest"]), "ground": int(rd["ground"]),
		"city": {"seed": cseed, "level": int(st["regions"][r]["level"]), "walls": CState.walls(st, r),
			"bld": city_buildings(st, r), "def": 1}}


static func _side_has(st: Dictionary, armies: Array, lead: int, f: int) -> bool:
	if lead >= 0 and CState.friendly(st, lead, f):
		return true
	for a in armies:
		if CState.friendly(st, int(a["f"]), f):
			return true
	return false


## Lay out one side's units (side 0 coordinates: x from the centre, "back"
## metres behind the front line). Main line: cavalry on the wings, bolt
## throwers at the line ends, infantry inside with pikes in the centre;
## missile troops 15 m ahead; stone throwers 25 m behind; past MAX_LINE
## units the rest of the infantry forms a second line.
static func _layout(entries: Array) -> Dictionary:
	var inf: Array = []
	var pikes: Array = []
	var cav: Array = []
	var screen: Array = []
	var bolts: Array = []
	var rear: Array = []
	for e in entries:
		var ty := UT.index_of(str(e["t"]))
		match UT.cls(ty):
			UT.CLS_PIKE:
				pikes.append(e)
			UT.CLS_CAV:
				cav.append(e)
			UT.CLS_MISSILE:
				screen.append(e)
			UT.CLS_ART:
				if UT.base_of(ty) == UT.STONE:
					rear.append(e)
				else:
					bolts.append(e)
			_:
				inf.append(e)
	# Infantry: pikes in the middle, the rest split to either side.
	var centre: Array = []
	var left_n := inf.size() / 2
	for k in left_n:
		centre.append(inf[k])
	centre.append_array(pikes)
	for k in range(left_n, inf.size()):
		centre.append(inf[k])
	var room := maxi(MAX_LINE - cav.size() - bolts.size(), 2)
	var second: Array = []
	while centre.size() > room:
		second.append(centre.pop_back())
	var line: Array = []
	for k in (cav.size() + 1) / 2:
		line.append(cav[k])
	for k in (bolts.size() + 1) / 2:
		line.append(bolts[k])
	line.append_array(centre)
	for k in range((bolts.size() + 1) / 2, bolts.size()):
		line.append(bolts[k])
	for k in range((cav.size() + 1) / 2, cav.size()):
		line.append(cav[k])
	var placed: Array = []
	var width := 0
	width = maxi(width, _row(line, 0, 4, placed))
	width = maxi(width, _row(screen, -SCREEN, 6, placed))
	width = maxi(width, _row(second, SECOND_LINE, 6, placed))
	width = maxi(width, _row(rear, SECOND_LINE + 25 if not second.is_empty() else 25, 8, placed))
	return {"placed": placed, "width": width, "lines": 2 if not second.is_empty() else 1}


static func _row(row: Array, back: int, gap: int, placed: Array) -> int:
	if row.is_empty():
		return 0
	var total := -gap
	for e in row:
		total += Scenarios._width_m(UT.index_of(str(e["t"])), int(e["n"])) + gap
	var x := -total / 2
	for e in row:
		var w := Scenarios._width_m(UT.index_of(str(e["t"])), int(e["n"]))
		placed.append({"e": e, "x": x + w / 2, "back": back})
		x += w + gap
	return total


## BattleSim.result() -> campaign outcome for crules.apply_outcome().
static func outcome_from_result(built: Dictionary, res: Dictionary, mode: String) -> Dictionary:
	var map: Array = built["map"]
	var sim_side: Array = built["sim_side"]
	var units: Array = []
	var gar: Array = built["garrison"]
	var gar_full := 0
	var gar_back := 0
	for g in gar:
		gar_full += int(g["full"])
	for r in res["units"]:
		var k := int(r["unit"])
		if k >= map.size():
			continue
		var m: Dictionary = map[k]
		var e := {"army": int(m["army"]), "unit": int(m["unit"]), "killed": int(r["killed"]),
			"routed": int(r["routed_off"]), "withdrawn": int(r["withdrawn"]), "remaining": int(r["remaining"])}
		var cn := int(m.get("n", 0))
		var sn := int(m.get("sim_n", cn))
		if sn > 0 and cn != sn:
			# Scaled-down battle (fast auto-resolve): scale the fates back up.
			e["killed"] = int(e["killed"]) * cn / sn
			e["routed"] = int(e["routed"]) * cn / sn
			e["withdrawn"] = int(e["withdrawn"]) * cn / sn
			e["remaining"] = maxi(cn - int(e["killed"]) - int(e["routed"]) - int(e["withdrawn"]), 0)
		units.append(e)
		if int(m["army"]) < 0:
			gar_back += int(e["remaining"]) + int(e["withdrawn"]) + int(e["routed"]) * CData.ROUT_RETURN / 100
	var w := int(res["winner"])
	var winner := 1
	if w == int(sim_side[0]):
		winner = 0
	return {"winner": winner, "mode": mode, "units": units,
		"garrison_pct": (gar_back * 100 / gar_full) if gar_full > 0 else 0,
		"sim_winner": w, "ticks": int(res["tick"])}


## Strength of each side of battle b for the formula and the AI:
## [attackers, defenders].
static func side_strengths(st: Dictionary, b: Dictionary) -> Array:
	var arm := CRules.battle_armies(st, b)
	var s := [0, 0]
	for side in 2:
		for a in arm[side]:
			s[side] += CState.strength(a)
	s[1] += garrison_strength(st, int(b["r"]))
	s[1] = s[1] * (100 + ground_bonus(int(b["r"]))) / 100
	return s


## Garrison strength including the wall bonus.
static func garrison_strength(st: Dictionary, r: int) -> int:
	var g := 0
	for u in CRules.garrison(st, r):
		var ty := UT.index_of(str(u["t"]))
		g += int(u["n"]) * UT.price_of(ty) / maxi(UT.size_of(ty), 1)
	return g * (100 + 15 * CState.walls(st, r)) / 100


## Defender's % bonus from the region's ground.
static func ground_bonus(r: int) -> int:
	var k := int(CData.REGIONS[r]["terrain"])
	if k == Terrain.K_HILL or k == Terrain.K_RIDGE:
		return 15
	if k == Terrain.K_VALLEY or k == Terrain.K_ROLLING:
		return 10
	return 5


## Attacker's chance to win battle b in per mille (formula model).
static func win_chance(sa: int, sd: int) -> int:
	var a := sa / 20
	var d := sd / 20
	var a3 := a * a * a
	var d3 := d * d * d
	if a3 + d3 <= 0:
		return 500
	return int(1000 * a3 / (a3 + d3))


## Formula outcome for battle b (uses and advances the state's RNG).
static func formula(st: Dictionary, b: Dictionary) -> Dictionary:
	var s := side_strengths(st, b)
	var p := win_chance(s[0], s[1])
	var winner := 0 if CState.rand(st, 1000) < p else 1
	var sw: int = maxi(s[winner], 1)
	var sl: int = s[1 - winner]
	# q = loser / winner strength in per mille.
	var q := clampi(sl * 1000 / sw, 0, 3000)
	var win_kill := clampi(q * 32 / 1000, 4, 45)              # % killed on the winning side
	var lose_kill := clampi(66 - q * 12 / 1000 + CState.rand(st, 11) - 5, 35, 80)
	var lose_rout := 20
	var arm := CRules.battle_armies(st, b)
	var units: Array = []
	for side in 2:
		var kill := win_kill if side == winner else lose_kill
		var rout := 5 if side == winner else lose_rout
		for a in arm[side]:
			for k in CState.unit_count(a):
				var n := int(a["units"][k]["n"])
				var kd := n * kill / 100
				var rt := n * rout / 100
				units.append({"army": int(a["id"]), "unit": k, "killed": kd, "routed": rt,
					"withdrawn": 0, "remaining": n - kd - rt})
	var gar := int(st["regions"][int(b["r"])]["gar"])
	var gpct := 0
	if winner == 1:
		gpct = gar * (100 - win_kill) / 100
	return {"winner": winner, "mode": "formula", "units": units, "garrison_pct": gpct}


## A battle the player left before it was decided: losses so far stand, the
## player's men still on the field withdraw, and the other side wins (sim
## side 0 is the player's).
static func outcome_forfeit(built: Dictionary, res: Dictionary) -> Dictionary:
	var r2 := res.duplicate(true)
	r2["winner"] = 1
	for u in r2["units"]:
		if int(u["side"]) == 0:
			u["withdrawn"] = int(u["withdrawn"]) + int(u["remaining"])
			u["remaining"] = 0
	var out := outcome_from_result(built, r2, "fought")
	out["forfeit"] = 1
	return out
