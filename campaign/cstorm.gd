extends RefCounted
## Hurricanes (N2b, a pack with ships and STORM_* numbers in its ships
## script; docs/CAMPAIGN.md "Hurricanes, captains and named galleons (N2b)").
## The season is the summer turn. At the end of the turn before it, storms
## form east of the Lesser Antilles; each storm moves at the end of every
## turn along a heading that may turn one point clockwise (west, then
## north-west, recurving north), sweeping a band of its radius: fleets in it
## lose hull and crew and may founder (galleons and canoes worst, sloops
## luckiest, ships in a friendly harbour much safer), ports lose trade and
## perhaps a building level, armies ashore lose a few men. The forecast cone
## (the two headings it likely takes, its radius round them) holds unless
## the storm swerves (STORM_SWERVE_PCT: a point beyond either side). Same discipline as the rest of campaign/: integers
## (positions in centi-cells), the state's RNG, arrays in index order.
##
## State (only in a pack with ships; optional): storms [{id, px, py (centre,
## centi-cells), h (heading 0 N .. 15 NNW, 16 points clockwise), v (centi-
## cells a move), r (radius, cells), life (moves left), born (turn), yr
## (year of its season), nm (name), tr [[x, y] past centres, cells], lost
## [[faction, ship key, x, y, name or ""]] (ships it sank), ports, men,
## gold (treasure it sank)}] sorted by id; next_storm; wrecks (CSea);
## stats storms, storm_ships, storm_ports, storm_men.

const CData := preload("res://campaign/cdata.gd")
const CState := preload("res://campaign/cstate.gd")
const CGrid := preload("res://campaign/cgrid.gd")
const CFleet := preload("res://campaign/cfleet.gd")

## Unit vectors x 100 of the 16 headings (0 N, 4 E, 8 S, 12 W; y grows south).
const DIR_X: Array[int] = [0, 38, 71, 92, 100, 92, 71, 38, 0, -38, -71, -92, -100, -92, -71, -38]
const DIR_Y: Array[int] = [-100, -92, -71, -38, 0, 38, 71, 92, 100, 92, 71, 38, 0, -38, -71, -92]


static func _rules() -> GDScript:
	return load("res://campaign/crules.gd")


static func _csea() -> GDScript:
	return load("res://campaign/csea.gd")


static func _capt() -> GDScript:
	return load("res://campaign/ccaptain.gd")


## The pack has hurricanes (its ships script says where they form).
static func pack_on() -> bool:
	return (CData.ship_const("STORM_BOX", []) as Array).size() == 4


static func on(st: Dictionary) -> bool:
	return st.has("fleets") and pack_on()


static func k(key: String, default: int) -> int:
	return int(CData.ship_const(key, default))


static func _pair(key: String, a: int, b: int) -> Array:
	var v: Array = CData.ship_const(key, [a, b])
	return [int(v[0]), int(v[1])] if v.size() >= 2 else [a, b]


static func storms(st: Dictionary) -> Array:
	return st.get("storms", [])


## Turn t is in the hurricane season (summer: the even turns).
static func season(t: int) -> bool:
	return t % 2 == 0


## The year of turn t (as CData.date_text).
static func year(t: int) -> int:
	return CData.START_YEAR - t / 2 if CData.ERA == "BC" else CData.START_YEAR + t / 2


static func _stat(st: Dictionary, key: String, n: int) -> void:
	var s: Dictionary = st["stats"]
	s[key] = int(s.get(key, 0)) + n


# -------------------------------------------------------------- geometry ---

## Centre of cell c in centi-cells.
static func cpx(c: int) -> int:
	return CGrid.cx(c) * 100 + 50


static func cpy(c: int) -> int:
	return CGrid.cy(c) * 100 + 50


## Where storm s ends its next move on heading h: [px, py].
static func next_point(s: Dictionary, h: int) -> Array:
	var hh := posmod(h, 16)
	return [int(s["px"]) + DIR_X[hh] * int(s["v"]) / 100, int(s["py"]) + DIR_Y[hh] * int(s["v"]) / 100]


## Squared distance (centi-cells) from point (px, py) to segment a-b.
static func seg_d2(px: int, py: int, ax: int, ay: int, bx: int, by: int) -> int:
	var dx := bx - ax
	var dy := by - ay
	var den := dx * dx + dy * dy
	var qx := ax
	var qy := ay
	if den > 0:
		var t := clampi((px - ax) * dx + (py - ay) * dy, 0, den)
		qx = ax + dx * t / den
		qy = ay + dy * t / den
	return (px - qx) * (px - qx) + (py - qy) * (py - qy)


## Cell c lies in storm s's forecast cone (within its radius + margin cells
## of either track it may take next).
static func in_cone(s: Dictionary, c: int, margin: int = 0) -> bool:
	var x := cpx(c)
	var y := cpy(c)
	var lim := (int(s["r"]) + margin) * 100
	var px := int(s["px"])
	var py := int(s["py"])
	var bb := lim + int(s["v"])
	if absi(x - px) > bb or absi(y - py) > bb:
		return false
	for dh in 2:
		var b := next_point(s, int(s["h"]) + dh)
		if seg_d2(x, y, px, py, int(b[0]), int(b[1])) <= lim * lim:
			return true
	return false


## Cell c is in the forecast cone of any storm (margin: extra cells).
static func danger(st: Dictionary, c: int, margin: int = 0) -> bool:
	for s in storms(st):
		if in_cone(s, c, margin):
			return true
	return false


## The flota's way home is threatened: a storm's cone within `margin` cells
## of the meeting dock or of the straight course from it to the exit.
static func threat_course(st: Dictionary, from: int, to: int, margin: int = 10) -> bool:
	if storms(st).is_empty() or from < 0:
		return false
	var pts: Array[int] = [from]
	if to >= 0:
		var n := maxi(CGrid.cheb(from, to) / 4, 1)
		for i in range(1, n + 1):
			pts.append(CGrid.at(CGrid.cx(from) + (CGrid.cx(to) - CGrid.cx(from)) * i / n,
				CGrid.cy(from) + (CGrid.cy(to) - CGrid.cy(from)) * i / n))
	for s in storms(st):
		for c in pts:
			if c >= 0 and in_cone(s, c, margin):
				return true
	return false


# -------------------------------------------------------------- the turn ---

## crules end of turn (CSea.after_turn): the storms strike and move, then
## new ones form for the season.
static func turn(st: Dictionary) -> void:
	if not on(st):
		return
	strike_all(st)
	form(st)


## End of turn: when the next turn is in the season, 0-2 storms form in
## STORM_BOX (event "storm", chronicle).
static func form(st: Dictionary) -> void:
	var t := int(st["turn"]) + 1
	if not season(t):
		return
	var chance: Array = CData.ship_const("STORM_FORM_PCT", [65, 15])
	var box: Array = CData.ship_const("STORM_BOX", [])
	var n := 0
	if CState.rand(st, 100) < int(chance[0]):
		n = 1
		if chance.size() > 1 and CState.rand(st, 100) < int(chance[1]):
			n = 2
	for i in n:
		var x := int(box[0]) + CState.rand(st, int(box[2]) - int(box[0]) + 1)
		var y := int(box[1]) + CState.rand(st, int(box[3]) - int(box[1]) + 1)
		var sp := _pair("STORM_SPEED", 3000, 4200)
		var rr := _pair("STORM_R", 4, 6)
		var lf := _pair("STORM_LIFE", 2, 3)
		var names: Array = CData.ship_const("STORM_NAMES", ["San Lorenzo"])
		var s := {"id": int(st.get("next_storm", 1)), "px": x * 100 + 50, "py": y * 100 + 50,
			"h": 12 + CState.rand(st, 2), "v": int(sp[0]) + CState.rand(st, int(sp[1]) - int(sp[0]) + 1),
			"r": int(rr[0]) + CState.rand(st, int(rr[1]) - int(rr[0]) + 1),
			"life": int(lf[0]) + CState.rand(st, int(lf[1]) - int(lf[0]) + 1), "born": int(st["turn"]), "yr": year(t),
			"nm": _name(st, names), "tr": [[x, y]], "lost": [], "ports": 0, "men": 0, "gold": 0}
		st["next_storm"] = int(s["id"]) + 1
		if not st.has("storms"):
			st["storms"] = []
		(st["storms"] as Array).append(s)
		_stat(st, "storms", 1)
		_rules().event(st, {"k": "storm", "id": int(s["id"]), "nm": str(s["nm"]), "yr": int(s["yr"]), "x": x, "y": y})


## A saint's name for a new storm, none of those at sea (by the state's RNG).
static func _name(st: Dictionary, names: Array) -> String:
	var used := {}
	for s in storms(st):
		used[str(s["nm"])] = 1
	var free: Array = []
	for n in names:
		if not used.has(str(n)):
			free.append(str(n))
	if free.is_empty():
		free = names
	return str(free[CState.rand(st, free.size())])


## End of turn: every storm moves (its heading may turn a point clockwise)
## and strikes what lies in its path; storms that run out of life or off
## the map blow out (event "storm_end", chronicle).
static func strike_all(st: Dictionary) -> void:
	if storms(st).is_empty():
		return
	var keep: Array = []
	for s in storms(st):
		var north := int(s["py"]) < k("STORM_NORTH_Y", 50) * 100
		var curve := k("STORM_CURVE_NORTH_PCT", 60) if north else k("STORM_CURVE_PCT", 35)
		var turn_by := 1 if CState.rand(st, 100) < curve else 0
		var sw := CState.rand(st, 100)
		if sw < k("STORM_SWERVE_PCT", 0):
			turn_by = 2 if sw % 2 == 0 else -1  # it swerves out of its cone: forecasts fail
		var h := posmod(int(s["h"]) + turn_by, 16)
		var b := next_point(s, h)
		strike(st, s, int(s["px"]), int(s["py"]), int(b[0]), int(b[1]))
		s["h"] = h
		s["px"] = int(b[0])
		s["py"] = int(b[1])
		s["life"] = int(s["life"]) - 1
		var c := CGrid.at(int(b[0]) / 100, int(b[1]) / 100) if int(b[0]) >= 0 and int(b[1]) >= 0 else -1
		if c >= 0:
			(s["tr"] as Array).append([CGrid.cx(c), CGrid.cy(c)])
			if CGrid.region(c) >= 0:
				s["r"] = maxi(int(s["r"]) - 1, k("STORM_R_MIN_LAND", 3))  # landfall
		if c < 0 or int(s["life"]) <= 0:
			var ev := {"k": "storm_end", "id": int(s["id"]), "nm": str(s["nm"]), "yr": int(s["yr"]), "lost": (s["lost"] as Array).duplicate(true),
				"ports": int(s["ports"]), "men": int(s["men"]), "gold": int(s["gold"])}
			var track: Array = s["tr"]
			ev["x"] = int(track[-1][0])
			ev["y"] = int(track[-1][1])
			_rules().event(st, ev)
			continue
		keep.append(s)
	st["storms"] = keep


## Zone of a point at squared distance d2 from the track of a storm of
## radius r: 2 the core, 1 the edge, 0 clear.
static func _zone(d2: int, r: int) -> int:
	var lim := r * 100
	if d2 > lim * lim:
		return 0
	var core := lim * k("STORM_CORE_PCT", 55) / 100
	return 2 if d2 <= core * core else 1


## Storm s sweeps from (ax, ay) to (bx, by): fleets, ports and armies in
## its band take their damage (event "storm_hit" when anything was hit).
static func strike(st: Dictionary, s: Dictionary, ax: int, ay: int, bx: int, by: int) -> void:
	var r := int(s["r"])
	var edge := k("STORM_EDGE_PCT", 35)
	var lost: Array = []
	var gold := 0
	var hit_ships := 0
	var at_sea := 0
	# Fleets.
	var gone: Array = []
	for fl in CFleet.fleets(st):
		var c := CFleet.cell(fl)
		var z := _zone(seg_d2(cpx(c), cpy(c), ax, ay, bx, by), r)
		if z == 0 or (fl["ships"] as Array).is_empty():
			continue
		var f := int(fl["f"])
		var pct := 100 if z == 2 else edge
		var in_port := CFleet.port_of(st, fl, f, true) >= 0
		if in_port:
			pct = pct * k("STORM_PORT_PCT", 20) / 100
		var keep: Array = []
		if not in_port:
			at_sea += (fl["ships"] as Array).size()
		for sh in fl["ships"]:
			hit_ships += 1
			var row := CData.ship_row(str(sh["t"]))
			var sink := mini(int(row.get("storm", 10)) * pct / 100 * (200 - int(sh["h"])) / 100, 90)
			if CState.rand(st, 100) < sink:
				lost.append([f, str(sh["t"]), CGrid.cx(c), CGrid.cy(c), str(sh.get("nm", ""))])
				if int(sh.get("g", 0)) > 0:
					gold += int(sh["g"])
					_csea().wreck(st, sh, c, "storm", -1)
				continue
			var dh := (k("STORM_HULL", 12) + CState.rand(st, k("STORM_HULL_RAND", 20) + 1)) * pct / 100
			sh["h"] = maxi(int(sh["h"]) - dh, 5)
			sh["c"] = maxi(int(sh["c"]) - dh / 2, 5)
			keep.append(sh)
		fl["ships"] = keep
		var sunk: Array = []
		CFleet._sink_extra(st, fl, sunk)
		if keep.is_empty():
			gone.append(fl)
	for fl in gone:
		_capt().fleet_lost(st, fl, "storm", -1, CFleet.cell(fl))
		(st["fleets"] as Array).erase(fl)
	# Ports.
	var ports: Array = []
	for rg in CData.region_count():
		var hb := CFleet.harbour(rg)
		if hb < 0:
			continue
		var z := _zone(seg_d2(cpx(hb), cpy(hb), ax, ay, bx, by), r)
		if z == 0:
			continue
		var rs: Dictionary = st["regions"][rg]
		var o := int(rs["owner"])
		var pct := 100 if z == 2 else edge
		var loss := 0
		if o >= 0:
			var fs: Dictionary = st["factions"][o]
			loss = mini(_csea().sea_trade(st, rg) * k("STORM_TRADE_PCT", 100) / 100 * pct / 100, maxi(int(fs["treasury"]), 0))
			fs["treasury"] = int(fs["treasury"]) - loss
		var chain := -1
		var slots: Array = rs["slots"]
		if not slots.is_empty() and CState.rand(st, 100) < k("STORM_BUILD_PCT", 30) * pct / 100:
			var i := CState.rand(st, slots.size())
			chain = int(slots[i][0])
			if int(slots[i][1]) > 1:
				slots[i] = [chain, int(slots[i][1]) - 1]
			else:
				slots.remove_at(i)
		ports.append([rg, loss, chain])
	# Armies ashore.
	var men := 0
	for a in st["armies"]:
		var c := CState.cell(a)
		var z := _zone(seg_d2(cpx(c), cpy(c), ax, ay, bx, by), r)
		if z == 0:
			continue
		var pct := k("STORM_MEN_PCT", 6) * (100 if z == 2 else edge) / 100
		for u in a["units"]:
			var n := int(u["n"])
			var d := mini(n * pct / 100, n - 1)
			if d > 0:
				u["n"] = n - d
				men += d
	(s["lost"] as Array).append_array(lost)
	s["ports"] = int(s["ports"]) + ports.size()
	s["men"] = int(s["men"]) + men
	s["gold"] = int(s["gold"]) + gold
	_stat(st, "storm_ships", lost.size())
	_stat(st, "storm_ports", ports.size())
	_stat(st, "storm_men", men)
	if lost.is_empty() and ports.is_empty() and men == 0 and hit_ships == 0:
		return
	_rules().event(st, {"k": "storm_hit", "id": int(s["id"]), "nm": str(s["nm"]), "yr": int(s["yr"]),
		"x0": ax / 100, "y0": ay / 100, "x1": bx / 100, "y1": by / 100, "lost": lost, "ships": hit_ships, "sea": at_sea, "ports": ports,
		"men": men, "gold": gold})
