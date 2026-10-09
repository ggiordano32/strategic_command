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
## AI profiles: the scenario carries "ai_skill" / "ai_style" per sim side
## (sim/ai_profile.gd): an AI-commanded side gets its lead faction's battle
## skill and personality (campaign/cai_profile.gd battle_skill / style;
## independents the battle skill setting), a side of the players (or one
## they command) Average / Balanced.
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
## tests/campaign_battles.gd); losses from the strength ratio. A field
## battle of a siege (sally, relief: settlement 0) counts the garrison on the
## owner's side without its walls and gives nobody the ground.
##
## odds(): the same formula as a prediction for any two groups of armies
## (the view's balance-of-power bar): strengths, the attacker's chance,
## expected losses per side and a band from decisive loss to decisive win.

const CData := preload("res://campaign/cdata.gd")
const CState := preload("res://campaign/cstate.gd")
const CRules := preload("res://campaign/crules.gd")
const UT := preload("res://sim/unit_types.gd")
const Scenarios := preload("res://sim/scenarios.gd")
const Terrain := preload("res://sim/terrain.gd")
const MapGen := preload("res://sim/mapgen.gd")
const CP := preload("res://campaign/cai_profile.gd")

const FRONT := 100       # m from the centre line to each side's front
const SECOND_LINE := 45  # m behind the first
const SCREEN := 15       # missile screen ahead of the line
const MAX_LINE := 12     # units in the first line before a second line forms
const EDGE_BAND := 110   # m added on a side of the field where reinforcements arrive
const EDGE_IN := 45      # m from the map edge to an arriving column's front
const LADDER_TURNS := 1  # an assault after a siege of this many turns brings ladders ...
const RAM_TURNS := 2     # ... and of this many a ram
const LADDER_SETS := [2, 3]  # ... sets of ladders after LADDER_TURNS, RAM_TURNS turns
const DEFAULT_TIME_LIMIT := 900  # s: the sim's own battle time limit (settings "time_limit")
const WIN_ROUT := 5      # formula: % routed on the winning side ...
const LOSE_ROUT := 20    # ... and on the losing side


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
	# Version 5 interceptions ("field"): armies only, the garrison stays in.
	var gar := CRules.garrison(st, r) if str(b.get("kind", "")) != "field" else []
	# Campaign side (0 attackers, 1 defenders) -> sim side.
	var def_on_0 := human_f >= 0 and _side_has(st, arm[1], int(b["def_f"]), human_f)
	var sim_side := [1, 0] if def_on_0 else [0, 1]
	var entries := [[], []]  # per campaign side: {army, unit, t, n, f}
	for s in 2:
		var field := 0
		for a in arm[s]:
			# The special kinds its missile troops carry: its wagons carry
			# stock of them (scenario "aks").
			var aks: Array = []
			for u0 in a["units"]:
				var ak0 := str(u0.get("ak", ""))
				if ak0 != "" and not aks.has(ak0):
					aks.append(ak0)
			for k in CState.unit_count(a):
				var u: Dictionary = a["units"][k]
				if int(u["n"]) <= 0 or field >= CData.BATTLE_SIDE_MAX:
					continue
				field += 1
				var ent := {"army": int(a["id"]), "unit": k, "t": str(u["t"]), "n": int(u["n"]), "f": int(a["f"])}
				if CState.stance(a) == CData.ST_FORCED:
					ent["morale"] = CData.FORCED_MORALE_PCT
				if u.has("ak"):
					ent["ak"] = str(u["ak"])  # its special ammunition kind
				if UT.stat(UT.index_of(str(u["t"])), "wagon") >= 0 and not aks.is_empty():
					ent["aks"] = aks
				entries[s].append(ent)
	for k in gar.size():
		var g: Dictionary = gar[k]
		if int(g["n"]) > 0:
			entries[1].append({"army": -1, "unit": k, "t": str(g["t"]), "n": int(g["n"]), "f": int(b["def_f"])})
	if int(b.get("settlement", 1)) != 0:
		return _build_settlement(st, b, human_f, scale_pct, entries, sim_side, gar)
	# Version 5: reinforcements arrive from the map edge facing the region
	# they come from (b["edge"]: compass sectors), turned so the lead
	# attacker's approach is the attackers' own edge.
	var edges := _edge_groups(b, entries)
	var layouts := [_layout(entries[0]), _layout(entries[1])]
	var width := 560
	for s in 2:
		width = maxi(width, int(layouts[s]["width"]) + 160)
	var two_lines := int(layouts[0]["lines"]) > 1 or int(layouts[1]["lines"]) > 1
	var height := 640 if two_lines else 560
	var side_edges := false
	var end_edges := false
	for g in edges:
		var ed := int(g["edge"])
		if ed == 1 or ed == 3:
			side_edges = true
		else:
			end_edges = true
		width = maxi(width, int(g["lay"]["width"]) + 160)
	if side_edges:
		width += 2 * EDGE_BAND
	if end_edges:
		height += 2 * EDGE_BAND
	width = mini(width, 960 + 2 * EDGE_BAND)
	width -= width % 4
	var units: Array = []
	var map: Array = []
	var ufac: Array = []
	var placed_all: Array = []  # [campaign side, x, y, face, entry]
	for cs in 2:
		var ss: int = sim_side[cs]
		for p in layouts[cs]["placed"]:
			var x := width / 2 + int(p["x"])
			var y := height / 2 + FRONT + int(p["back"])
			var face := Scenarios.FACE_UP
			if ss == 1:
				x = width - x
				y = height - y
				face = Scenarios.FACE_DOWN
			placed_all.append([cs, x, y, face, p["e"]])
	for g in edges:
		_place_edge(g, width, height, placed_all)
	for pa in placed_all:
		var cs: int = pa[0]
		var ss: int = sim_side[cs]
		var e: Dictionary = pa[4]
		var ty := UT.index_of(str(e["t"]))
		var x: int = pa[1]
		var y: int = pa[2]
		var face: int = pa[3]
		var cnt := int(e["n"])
		if scale_pct != 100:
			cnt = maxi(cnt * scale_pct / 100, mini(cnt, 8))
			if UT.cls(ty) == UT.CLS_ART:
				cnt = int(e["n"])  # engines and crews are not scaled
		var su := Scenarios.unit(ss, ty, cnt, x, y, face)
		if int(e.get("morale", 100)) != 100:
			su["morale_pct"] = int(e["morale"])  # version 6: caught on a forced march
		_unit_extras(su, e)
		units.append(su)
		map.append({"side": cs, "army": int(e["army"]), "unit": int(e["unit"]), "n": int(e["n"]), "sim_n": cnt})
		ufac.append(int(e["f"]))
	var terrain := {"kind": int(CData.REGIONS[r]["terrain"]), "seed": battle_seed(st, r, 1),
		"forest": int(CData.REGIONS[r]["forest"]), "ground": int(CData.REGIONS[r]["ground"])}
	var ai: Array = [0, 1] if human_f < 0 else [1]
	var controller: Array = []
	for f in ufac:
		controller.append(human_f if human_f >= 0 and CState.friendly(st, int(f), human_f) else -1)
	var prof := _ai_profiles(st, b, sim_side, ai)
	var scn := {"width_m": width, "height_m": height, "ai_sides": ai, "ai_skill": prof[0],
		"ai_style": prof[1], "units": units, "terrain": terrain}
	_deployment(st, scn, human_f)
	_time_limit(st, scn)
	return {"scenario": scn,
		"seed": battle_seed(st, r, 2), "map": map, "sim_side": sim_side, "garrison": gar,
		"unit_faction": ufac, "controller": controller, "battle": int(b["id"]), "region": r}


## A battle fought by players (human_f >= 0) gets the campaign's deployment
## phase (settings "deploy_time", seconds; absent = none: older campaigns
## and every auto-resolved battle). Field battles get their zones here
## (each side's half, flank arrivals boxed); settlement scenarios carry
## theirs.
static func _deployment(st: Dictionary, scn: Dictionary, human_f: int) -> void:
	var dt := int((st.get("settings", {}) as Dictionary).get("deploy_time", 0))
	if human_f < 0 or dt <= 0:
		return
	scn["deploy_time"] = dt
	if not scn.has("deploy_zones"):
		scn["deploy_zones"] = Scenarios.field_zones(scn)


## The campaign's battle time limit (settings "time_limit", seconds; absent
## = the sim's 15 minutes: older campaigns hash as before).
static func _time_limit(st: Dictionary, scn: Dictionary) -> void:
	var tl := int((st.get("settings", {}) as Dictionary).get("time_limit", 0))
	if tl > 0 and tl != DEFAULT_TIME_LIMIT:
		scn["time_limit"] = tl


## Turns region r has been besieged for (the current turn less the siege's
## first), -1 if it is not besieged. No state of its own: siege entries
## keep the turn they began (docs/CAMPAIGN.md "Siege equipment").
static func siege_turns(st: Dictionary, r: int) -> int:
	var sg := CState.siege_at(st, r)
	if sg.is_empty():
		return -1
	return maxi(int(st["turn"]) - int(sg["turn"]), 0)


## The attackers' siege equipment for battle b (Scenarios.settlement
## "equip"): an assault after a siege of a full turn or more brings two
## sets of ladders, of two turns or more three and a ram; an assault on
## arrival (and any other battle) nothing but the armies' own artillery.
static func siege_equipment(st: Dictionary, b: Dictionary) -> Dictionary:
	if str(b.get("kind", "")) != "assault":
		return {}
	var sg := CState.siege_at(st, int(b["r"]))
	if sg.is_empty():
		return {}
	var n := maxi(int(b.get("turn", st["turn"])) - int(sg["turn"]), 0)
	var out := {}
	if n >= LADDER_TURNS:
		out["ladders"] = int(LADDER_SETS[1 if n >= RAM_TURNS else 0])
	if n >= RAM_TURNS:
		out["ram"] = 1
	return out


## One line for the siege panel on what an assault on besieged region r
## brings this turn and when more comes ("" for an open town or no siege).
static func equipment_text(st: Dictionary, r: int) -> String:
	var n := siege_turns(st, r)
	if n < 0 or CState.walls(st, r) <= 0:
		return ""
	if n >= RAM_TURNS:
		return "Siege equipment: %d sets of ladders and a ram." % int(LADDER_SETS[1])
	if n >= LADDER_TURNS:
		return "Siege equipment: %d sets of ladders; a ram next turn." % int(LADDER_SETS[0])
	return "Siege equipment: none yet (artillery only); ladders next turn, a ram in %d turns." % RAM_TURNS


## [ai_skill per sim side, ai_style per sim side] for battle b: an AI side
## its lead faction's (attacker / defender), the players' sides Average /
## Balanced.
static func _ai_profiles(st: Dictionary, b: Dictionary, sim_side: Array, ai: Array) -> Array:
	var sk := [CP.AVERAGE, CP.AVERAGE]
	var sy := [CP.BALANCED, CP.BALANCED]
	for cs in 2:
		var ss := int(sim_side[cs])
		if not ai.has(ss):
			continue
		var f := int(b["att_f"]) if cs == 0 else int(b["def_f"])
		if f >= 0 and CState.is_human(st, f):
			continue
		sk[ss] = CP.battle_skill(st, f)
		sy[ss] = CP.style(st, f)
	return [sk, sy]


## Reinforcing armies with an edge (b["edge"], version 5) taken out of
## `entries` into groups {side, edge (0 the attackers' end, 1 the
## attackers' left, 2 the defenders' end, 3 the attackers' right, as seen
## by the attackers facing the enemy), corner (-1, 0, 1: along that edge),
## entries, lay}. Sectors relative to the attackers' approach (the sector
## the lead attacker came from; south if unknown): 0 = behind the
## attackers, 4 = behind the defenders, 2 / 6 the attackers' left / right
## flanks (compass clockwise, the attackers facing the enemy), odd =
## corners (put on the nearer end edge, toward that flank: corner -1 left,
## +1 right).
static func _edge_groups(b: Dictionary, entries: Array) -> Array:
	var out: Array = []
	var list: Array = b.get("edge", [])
	if list.is_empty() or int(b.get("settlement", 1)) != 0:
		return out
	var r := int(b["r"])
	var approach := 4  # unknown: attackers from the south
	if int(b.get("app", -1)) >= 0:
		approach = int(b["app"])  # version 6: the lead attacker's bearing
	else:
		for pr in b.get("from", []):
			if (b["att"] as Array).has(int(pr[0])) and int(pr[1]) >= 0:
				var sc := CData.sector(r, int(pr[1]))
				if sc >= 0:
					approach = sc
					break
	var groups := {}
	var order: Array = []
	for pr in list:
		var sc := int(pr[1])
		if sc < 0:
			continue
		var rel := posmod(sc - approach, 8)
		var edge := 0
		var corner := 0
		match rel:
			0:
				edge = 0
			1:
				edge = 0
				corner = -1
			2:
				edge = 1
			3:
				edge = 2
				corner = -1
			4:
				edge = 2
			5:
				edge = 2
				corner = 1
			6:
				edge = 3
			7:
				edge = 0
				corner = 1
		var aid := int(pr[0])
		for cs in 2:
			var keep: Array = []
			var mine: Array = []
			for e in entries[cs]:
				if int(e["army"]) == aid:
					mine.append(e)
				else:
					keep.append(e)
			if mine.is_empty():
				continue
			entries[cs] = keep
			var key := "%d_%d_%d" % [cs, edge, corner]
			if not groups.has(key):
				groups[key] = {"side": cs, "edge": edge, "corner": corner, "entries": []}
				order.append(key)
			(groups[key]["entries"] as Array).append_array(mine)
	for key in order:
		var g: Dictionary = groups[key]
		g["lay"] = _layout(g["entries"])
		out.append(g)
	return out


## Place an edge group on the field (sim coordinates; the attackers' end is
## where sim side sim_side[0] stands): a line facing inwards EDGE_IN m from
## that edge. Appends [campaign side, x, y, face, entry] to placed_all.
static func _place_edge(g: Dictionary, width: int, height: int, placed_all: Array) -> void:
	# Where the attackers stand: find any attacker entry already placed.
	var att_bottom := true
	for pa in placed_all:
		if int(pa[0]) == 0:
			att_bottom = int(pa[2]) > height / 2
			break
	var edge := int(g["edge"])
	var corner := int(g["corner"])
	# Screen edge: 0 bottom, 1 left, 2 top, 3 right.
	var scr := edge
	if att_bottom:
		scr = [0, 1, 2, 3][edge]
	else:
		scr = [2, 3, 0, 1][edge]
	var lay: Dictionary = g["lay"]
	var shift := corner * width / 4 * (1 if att_bottom else -1)
	for p in lay["placed"]:
		var e: Dictionary = p["e"]
		var along := int(p["x"])
		var back := int(p["back"])
		var x := 0
		var y := 0
		var face := Scenarios.FACE_UP
		match scr:
			0:
				x = width / 2 + along + shift
				y = height - EDGE_IN + back
				face = Scenarios.FACE_UP
			2:
				x = width / 2 - along + shift
				y = EDGE_IN - back
				face = Scenarios.FACE_DOWN
			1:
				x = EDGE_IN - back
				y = height / 2 + along
				face = Scenarios.FACE_RIGHT
			3:
				x = width - EDGE_IN + back
				y = height / 2 - along
				face = Scenarios.FACE_LEFT
		x = clampi(x, 12, width - 12)
		y = clampi(y, 12, height - 12)
		placed_all.append([int(g["side"]), x, y, face, e])


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
	var city := city_dict(st, r)
	var terr := {"kind": int(rd["terrain"]), "seed": (cseed ^ 0x2545F491) & 0x7FFFFFFF,
		"forest": int(rd["forest"]), "ground": int(rd["ground"])}
	var ai: Array = [0, 1] if human_f < 0 else [1]
	var res := Scenarios.settlement(city, terr, lists[0], lists[1], int(sim_side[1]), ai, siege_equipment(st, b))
	var sunits: Array = res["scenario"]["units"]
	for k in mini(sunits.size(), (res["order"] as Array).size()):
		var o0: Array = res["order"][k]
		_unit_extras(sunits[k], entries[int(o0[0])][int(o0[1])])
	# The city's tower engines carry the owner's special kind for them (heavy
	# bolts), as a unit of the owner recruited there would.
	var tak := UT.ammo_index(CRules.ammo_for(st, CState.owner(st, r), r, "tower_bolt"))
	if tak >= 0:
		res["scenario"]["tower_ak"] = tak
	var prof := _ai_profiles(st, b, sim_side, ai)
	res["scenario"]["ai_skill"] = prof[0]
	res["scenario"]["ai_style"] = prof[1]
	_deployment(st, res["scenario"], human_f)
	_time_limit(st, res["scenario"])
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
		"garrison": gar, "unit_faction": ufac, "controller": controller, "battle": int(b["id"]), "region": r,
		"owner": int(st["regions"][r]["owner"])}


## Scenario unit su from campaign entry e: its special ammunition kind
## (scenario "ak", a UnitTypes.AMMO row).
static func _unit_extras(su: Dictionary, e: Dictionary) -> void:
	if e.has("ak"):
		var k := UT.ammo_index(str(e["ak"]))
		if k >= 0:
			su["ak"] = k
	if e.has("aks"):
		var ks: Array = []
		for a in e["aks"]:
			var k2 := UT.ammo_index(str(a))
			if k2 >= 0:
				ks.append(k2)
		su["aks"] = ks


## Settlement r's city dictionary for the battle map (integers only):
## geometry (seed, level, walls, bld, plan = the founder's culture, coast =
## a port) and view-only dressing (founder, owner = the current owner's
## culture, banner = owner faction, bstyle = culture that built each entry
## of bld at its current level, hstyle = culture of the houses that came
## with each settlement level). def (the defending sim side) is set by
## Scenarios.settlement unless given (>= 0).
static func city_dict(st: Dictionary, r: int, def_side: int = -1) -> Dictionary:
	var bld := city_buildings(st, r)
	var bstyle: Array = []
	for c in bld:
		bstyle.append(CState.builder_culture(st, r, int(c), CState.building(st, r, int(c))))
	var hstyle: Array = []
	for lv in 3:
		hstyle.append(CState.builder_culture(st, r, -1, lv) if lv > 0 else CData.region_culture(r))
	var d := {"seed": CState.city_seed(st, r), "level": int(st["regions"][r]["level"]),
		"walls": CState.walls(st, r), "bld": bld, "plan": CData.region_culture(r),
		"coast": 1 if CData.is_port(r) else 0, "founder": CData.region_culture(r),
		"owner": CState.owner_culture(st, r), "banner": CState.owner(st, r), "bstyle": bstyle,
		"hstyle": hstyle}
	if def_side >= 0:
		d["def"] = def_side
	return d


## "Greek city on a coastal hill, held by Rome" (region panel caption).
static func city_caption(st: Dictionary, r: int) -> String:
	var rd: Dictionary = CData.REGIONS[r]
	# The site comes from the terrain kind and the city seed (MapGen.site_of).
	var txt := MapGen.describe(CData.region_culture(r), int(st["regions"][r]["level"]), int(rd["terrain"]),
		CState.city_seed(st, r), 1 if CData.is_port(r) else 0)
	var o := CState.owner(st, r)
	return txt + (", held by %s" % CData.faction_name(o) if o >= 0 else ", independent")


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
		"city": city_dict(st, r, 1)}


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
		if UT.stat(ty, "cmd_r") > 0:
			rear.append(e)  # the general behind the centre
			continue
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


## BattleSim.result() -> campaign outcome for crules.apply_outcome(). Each
## unit row: army, unit, killed, routed, withdrawn, remaining; a fought
## battle's rows (mode other than "auto") also carry "kills" (enemies its
## men killed), which the rules ignore and the battle screen shows.
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
		if mode != "auto":
			# A fought battle: the enemies each unit's men killed (optional
			# key; auto-resolved battles leave it out).
			e["kills"] = int(r.get("kills", 0)) * cn / sn if sn > 0 and cn != sn else int(r.get("kills", 0))
		units.append(e)
		if int(m["army"]) < 0:
			gar_back += int(e["remaining"]) + int(e["withdrawn"]) + int(e["routed"]) * CData.ROUT_RETURN / 100
	var w := int(res["winner"])
	var winner := 1
	if w == int(sim_side[0]):
		winner = 0
	var out := {"winner": winner, "mode": mode, "units": units,
		"garrison_pct": (gar_back * 100 / gar_full) if gar_full > 0 else 0,
		"sim_winner": w, "ticks": int(res["tick"])}
	if w != int(sim_side[0]) and w != int(sim_side[1]):
		out["draw"] = 1  # mutual destruction or time out
	return out


## Strength of each side of battle b for the formula and the AI:
## [attackers, defenders].
static func side_strengths(st: Dictionary, b: Dictionary) -> Array:
	var arm := CRules.battle_armies(st, b)
	var gs := -1 if str(b.get("kind", "")) == "field" else 1  # version 5 field battles: no garrison
	return strengths(st, arm[0], arm[1], int(b["r"]), int(b.get("settlement", 1)) != 0, gs)


## Formula strengths [attackers, defenders] of two groups of armies in
## region r. A settlement battle: the garrison (with its walls) joins the
## defenders, who also get the ground. A field battle: the garrison (without
## walls) joins side gar_side (0, 1, or -1: not there); no ground bonus.
## gar_side -2: 1 for a settlement battle, -1 for a field battle.
static func strengths(st: Dictionary, attackers: Array, defenders: Array, r: int, settlement: bool,
		gar_side: int = -2) -> Array:
	var s := [0, 0]
	for a in attackers:
		s[0] += CState.strength(a) * _stance_pct(a, false) / 100
	for a in defenders:
		s[1] += CState.strength(a) * _stance_pct(a, not settlement) / 100
	var gs := gar_side
	if gs == -2:
		gs = 1 if settlement else -1
	if settlement:
		if gs >= 0:
			s[gs] += garrison_strength(st, r)
		s[1] = s[1] * (100 + ground_bonus(r)) / 100
	elif gs >= 0:
		s[gs] += garrison_men_strength(st, r)
	return s


## Version 6 stances in the formula: a fortified army defending in the
## field counts FORTIFY_DEF_PCT %, an army caught on a forced march
## FORCED_DEF_PCT % (stance values 2-4 exist only in version 6 states).
static func _stance_pct(a: Dictionary, field_def: bool) -> int:
	match CState.stance(a):
		CData.ST_FORCED:
			return CData.FORCED_DEF_PCT
		CData.ST_FORTIFY:
			return CData.FORTIFY_DEF_PCT if field_def else 100
	return 100


## Garrison strength including the wall bonus.
static func garrison_strength(st: Dictionary, r: int) -> int:
	return garrison_men_strength(st, r) * (100 + 15 * CState.walls(st, r)) / 100


## Garrison strength in the open (no walls). A pure function of the
## region's owner, level, walls and garrison strength, so it is memoised.
static func garrison_men_strength(st: Dictionary, r: int) -> int:
	var rs: Dictionary = st["regions"][r]
	var key := "%d:%d:%d:%d:%d" % [r, int(rs["owner"]), int(rs["level"]), CState.walls(st, r), int(rs["gar"])]
	if _gar_memo.has(key):
		return int(_gar_memo[key])
	var g := 0
	for u in CRules.garrison(st, r):
		var ty := UT.index_of(str(u["t"]))
		g += int(u["n"]) * UT.price_of(ty) / maxi(UT.size_of(ty), 1)
	if _gar_memo.size() > 20000:
		_gar_memo.clear()
	_gar_memo[key] = g
	return g


static var _gar_memo := {}


## The formula's prediction for attackers against defenders in region r
## (see strengths() for settlement and gar_side): {att, def (strengths),
## share (attackers' % of the total), win (attacker's chance, %), win_pm
## (per mille), att_loss, def_loss (expected % of men lost for good:
## killed, and the routed who do not come back), band 0 decisive loss,
## 1 loss, 2 even, 3 win, 4 decisive win (for the attackers)}.
static func odds(st: Dictionary, attackers: Array, defenders: Array, r: int, settlement: bool,
		gar_side: int = -2) -> Dictionary:
	var s := strengths(st, attackers, defenders, r, settlement, gar_side)
	return odds_of(s[0], s[1])


## odds() for battle b as it stands.
static func battle_odds(st: Dictionary, b: Dictionary) -> Dictionary:
	var s := side_strengths(st, b)
	return odds_of(s[0], s[1])


static func odds_of(sa: int, sd: int) -> Dictionary:
	var p := win_chance(sa, sd)
	var q_att_wins := clampi(sd * 1000 / maxi(sa, 1), 0, 3000)
	var q_def_wins := clampi(sa * 1000 / maxi(sd, 1), 0, 3000)
	var att_loss := (p * _win_loss_pm(q_att_wins) + (1000 - p) * _lose_loss_pm(q_def_wins)) / 10000
	var def_loss := (p * _lose_loss_pm(q_att_wins) + (1000 - p) * _win_loss_pm(q_def_wins)) / 10000
	var band := 2
	if p < 150:
		band = 0
	elif p < 400:
		band = 1
	elif p > 850:
		band = 4
	elif p > 600:
		band = 3
	return {"att": sa, "def": sd, "share": sa * 100 / maxi(sa + sd, 1), "win": (p + 5) / 10, "win_pm": p,
		"att_loss": att_loss, "def_loss": def_loss, "band": band}


## Men lost for good by the winner (per mille): killed + the routed who do
## not come back (formula()).
static func _win_loss_pm(q: int) -> int:
	return _win_kill(q) * 10 + WIN_ROUT * (100 - CData.ROUT_RETURN) / 10


static func _lose_loss_pm(q: int) -> int:
	return clampi(66 - q * 12 / 1000, 35, 80) * 10 + LOSE_ROUT * (100 - CData.ROUT_RETURN) / 10


static func _win_kill(q: int) -> int:
	return clampi(q * 32 / 1000, 4, 45)


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
	var win_kill := _win_kill(q)                               # % killed on the winning side
	var lose_kill := clampi(66 - q * 12 / 1000 + CState.rand(st, 11) - 5, 35, 80)
	var arm := CRules.battle_armies(st, b)
	var units: Array = []
	for side in 2:
		var kill := win_kill if side == winner else lose_kill
		var rout := WIN_ROUT if side == winner else LOSE_ROUT
		for a in arm[side]:
			for k in CState.unit_count(a):
				var n := int(a["units"][k]["n"])
				var kd := n * kill / 100
				var rt := n * rout / 100
				units.append({"army": int(a["id"]), "unit": k, "killed": kd, "routed": rt,
					"withdrawn": 0, "remaining": n - kd - rt})
	var gar := int(st["regions"][int(b["r"])]["gar"])
	var gpct := 0
	if str(b.get("kind", "")) == "field":
		gpct = gar  # the garrison was not in it
	elif winner == 1:
		gpct = gar * (100 - win_kill) / 100
	elif int(b.get("settlement", 1)) == 0:
		gpct = gar * (100 - lose_kill) / 100  # beaten in the field, back behind the walls
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
