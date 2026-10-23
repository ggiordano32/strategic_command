class_name CTown
extends RefCounted
## The town plan shared by the overworld view and the battle map (rules side: integers, no RNG, no Dictionary
## iteration, nothing Node or float). The plan is NOT campaign state: it is static baked data plus a pure function of
## (state facts), so it needs no CState.VERSION bump, but it must be the same on every client.
##
## site(r): the baked record of region r's town (campaign/data/town_sites_<pack>.gd, written by tools/town_bake.gd from
## the overworld generator game/campaign/town_plan.gd): integers in decimetres in a local frame (the file: centimetres) (origin the town
## centre, x east, y south, the frame the overworld pieces use; one metre of a piece is 1.2 map px).
##   foot       PackedInt32Array [x0,y0,x1,y1,...] the full-size footprint (closed polygon, 48 vertices)
##   shore      PackedInt32Array [x,y,...] the harbour shore polyline, [] inland (seaward end first or last: see mouth)
##   mouth0 / mouth1  [x,y] the harbour mouth's seaward headland / its other end ([] without a shore)
##   high       [x,y] the highest ground in the outer footprint ([] none)
##   sea_dir    0..1023 towards the sea (0 east, 256 north, anticlockwise), -1 inland
##   streets    [[x0,y0,x1,y1],...] the street segments;  plaza [x,y,w,h]
##   lots       [[x,y,yaw0_7,size, hh, burn],...] house slots in fill order (size = collision radius dm, hh = the
##              colour / type hash, burn = 0..99 sack hash: baked so the view does not depend on rounding)
##   steep      16 sector flags (1 = slope over 30 per cent at 0.7 of the radius)
##   coast      PackedByteArray 48 x 48, 1 = land, 25 m a cell centred on the town (row-major, row 0 north)
## and the extras (also dm here): lines (street polylines), shore_n ([nx, ny, offset] per shore point, unit normals
## in 1/1000), cdir / up / axis / church_dir (unit vectors, 1/10000), cdist (dm, -1 none), near_sea, hill, church, p0,
## wc (the world centre, 1/1000 map px). The file itself is in centimetres; CTown.baked(r) gives it as written,
## with rad (24 footprint radii), ring_road, ring (round-village slots), fields, clear_r: what the overworld view
## redraws the very same town from.
##
## plan(st, r): what the state shows of the town: kind, level, walls, harbour, shipyard, owner, scale, the scaled
## footprint, the wall trace, the gates, the landmarks (real pieces with their size) and the civic piece.

const CData := preload("res://campaign/cdata.gd")
const CState := preload("res://campaign/cstate.gd")
const CFleet := preload("res://campaign/cfleet.gd")
const CSea := preload("res://campaign/csea.gd")
const MapGen := preload("res://sim/mapgen.gd")
const FixedMath := preload("res://sim/fixed_math.gd")

const LVL_S := [620, 800, 1000]       # footprint scale by level, per mille
const STYLE_S := 920                  # native / maya / haven towns, per mille
const WALL_S := 930                   # the wall runs at this share of the footprint, per mille
const COAST_N := 48
const COAST_CELL := 250               # dm a coast cell (25 m)
## Pieces whose landmark is a fort with an inside (the battle map builds a citadel ring), civic ones, props.
const FORT_PIECES := ["morro", "fuerza", "san_felipe", "morro_sj", "harbour_fort", "san_marcos", "alcazar", "ulua",
	"fort_charles", "rock_fort", "byrsa", "euryalus", "acropolis", "seawall"]
const CIVIC_PIECES := ["greek_temple", "twin_cathedral", "capitol", "itza_temple", "temple", "basilica", "cathedral", "church", "chapel"]

## Collision radius, half width, half depth, height of a piece, decimetres.
const PD := {
	"house_s": [30, 32, 27, 130], "house_m": [30, 29, 25, 200], "adobe": [32, 29, 24, 60],
	"chapel": [47, 29, 45, 216], "church": [66, 44, 70, 312], "cathedral": [76, 50, 79, 343], "mansion": [49, 45, 32, 128],
	"fort": [94, 86, 86, 158], "fountain": [32, 30, 30, 60], "well": [16, 14, 14, 55],
	"hut": [26, 24, 24, 110], "hut_big": [36, 34, 34, 140], "palapa": [26, 26, 22, 80], "totem": [12, 10, 10, 240],
	"maya_house": [30, 28, 22, 80], "maya_pyramid": [108, 97, 97, 288], "stela": [10, 10, 5, 100],
	"shack_a": [30, 28, 22, 100], "shack_b": [30, 28, 22, 100], "tent": [28, 26, 21, 60], "cannon": [14, 14, 9, 25],
	"barrels": [20, 18, 18, 25], "hullframe": [60, 60, 18, 100], "rowboat": [28, 30, 16, 20], "skull_rock": [40, 40, 35, 140],
	"flagpole": [6, 5, 5, 180], "roman_house": [32, 30, 26, 100], "hovel": [28, 26, 22, 90], "shrine": [38, 34, 34, 120],
	"temple": [66, 66, 46, 216], "basilica": [68, 64, 34, 144], "tower_rome": [34, 32, 32, 280],
	"pal_wall": [0, 30, 8, 80], "pal_post": [0, 10, 10, 130], "pal_gate": [0, 44, 10, 130],
	"stone_wall": [0, 30, 16, 90], "stone_tower": [0, 30, 29, 200], "stone_gate": [0, 46, 24, 220],
	"bast_wall": [0, 30, 22, 80], "bast_point": [0, 44, 42, 110], "bast_gate": [0, 46, 26, 180],
	"quay": [0, 30, 18, 15], "pier": [0, 20, 19, 20], "crane": [20, 14, 14, 220], "warehouse": [60, 66, 38, 150],
	"shed": [50, 60, 36, 140], "slipway": [0, 90, 42, 40], "lighthouse": [32, 35, 35, 440], "canoe": [24, 24, 9, 15],
	"tree_b1": [18, 26, 23, 100], "tree_b2": [20, 30, 26, 100], "palm_a": [10, 16, 14, 130], "palm_b": [10, 16, 14, 140],
	"orange": [12, 19, 17, 70],
	"morro": [140, 130, 110, 460], "fuerza": [90, 95, 85, 240], "san_felipe": [130, 140, 120, 480], "morro_sj": [140, 145, 90, 420],
	"harbour_fort": [80, 80, 65, 240], "san_marcos": [150, 160, 160, 300], "alcazar": [110, 125, 60, 280], "ulua": [140, 130, 100, 320],
	"itza_temple": [115, 110, 110, 580], "fort_charles": [100, 100, 70, 240], "tavern": [50, 48, 36, 160], "gallows": [26, 26, 20, 150],
	"rock_fort": [60, 65, 60, 400], "careened": [65, 65, 35, 80], "baluarte": [0, 46, 48, 120], "twin_cathedral": [80, 60, 85, 560],
	"capitol": [130, 105, 95, 400], "byrsa": [160, 150, 140, 360], "cothon": [145, 145, 145, 120], "euryalus": [150, 145, 90, 300],
	"acropolis": [160, 160, 140, 400], "greek_temple": [85, 80, 55, 260], "burnt": [30, 27, 23, 140], "camp_tent": [30, 28, 24, 80], "camp_flag": [6, 5, 5, 200],
	"camp_fire": [13, 13, 13, 40], "camp_stakes": [38, 10, 10, 40], "camp_earth": [36, 14, 14, 30],
	"longhouse": [62, 62, 30, 90], "rack": [23, 21, 9, 40], "stilt_house": [30, 28, 24, 100], "maya_platform": [64, 60, 60, 80],
}

## Landmarks by region key. p piece, at where (mouth0 = the harbour mouth's seaward headland, mouth1 = its other end,
## high = the highest ground, offshore = on a rock in the roads, plaza_sea = between the plaza and the sea,
## waterfront / beach = a row along the shore, cothon = by the water), in = inset in decimetres, face "land" = the
## front towards the town, wl / lv = least walls / level that show it, fort = it is the town's harbour fort (the
## generic one stays away), n = count, haven = only while a pirate haven.
const LM := {
	"havana": [{"p": "morro", "at": "mouth0", "in": 50, "face": "land", "wl": 1, "fort": true}, {"p": "fuerza", "at": "mouth1", "in": 40, "wl": 1, "fort": true}],
	"cartagena": [{"p": "seawall", "wl": 2, "fort": true}, {"p": "san_felipe", "at": "high", "wl": 1}],
	"san_juan": [{"p": "morro_sj", "at": "mouth0", "in": 50, "face": "land", "wl": 1, "fort": true}],
	"portobelo": [{"p": "harbour_fort", "at": "mouth0", "in": 30, "wl": 1, "fort": true}, {"p": "harbour_fort", "at": "mouth1", "in": 30, "wl": 1, "fort": true}],
	"st_augustine": [{"p": "san_marcos", "at": "mouth1", "in": 120, "wl": 2, "fort": true}],
	"santo_domingo": [{"p": "alcazar", "at": "plaza_sea", "lv": 1}],
	"veracruz": [{"p": "ulua", "at": "offshore", "wl": 1, "fort": true}],
	"port_royal": [{"p": "fort_charles", "at": "mouth0", "in": 40, "wl": 1, "fort": true}, {"p": "gallows", "at": "mouth1", "in": 20}, {"p": "tavern", "at": "waterfront", "n": 3}],
	"port_de_paix": [{"p": "rock_fort", "at": "high", "wl": 1, "fort": true}, {"p": "careened", "at": "beach", "n": 2, "haven": true}],
	"zeugitana": [{"p": "byrsa", "at": "high", "lv": 1}, {"p": "cothon", "at": "cothon", "lv": 1}],
	"sicilia_or": [{"p": "euryalus", "at": "high", "lv": 1}],
	"attica": [{"p": "acropolis", "at": "high"}],
	"massalia": [{"p": "greek_temple", "at": "high"}],
}

static var _pack := ""
static var _data := {}
static var _sites := {}


static func _sync() -> void:
	if _pack == CData.pack and not _data.is_empty():
		return
	_pack = CData.pack
	_sites = {}
	var path := "res://campaign/data/town_sites_%s.gd" % _pack
	_data = {}
	if ResourceLoader.exists(path):
		var scr = load(path)
		_data = (scr.get_script_constant_map())["SITES"]


## True when the active pack has baked sites.
static func has_sites() -> bool:
	_sync()
	return not _data.is_empty()


## The baked site of region r (a new Dictionary view of the record: packed arrays decoded once, cached), {} when
## the pack has none for it.
static func site(r: int) -> Dictionary:
	_sync()
	if _sites.has(r):
		return _sites[r]
	var key := str(CData.REGIONS[r]["key"])
	var out := {}
	if _data.has(key):
		out = _decode(_data[key] as Dictionary)
		out["r"] = r
	_sites[r] = out
	return out


static func _pack_arr(a: Array) -> PackedInt32Array:
	return PackedInt32Array(a)


## Centimetres (the baked unit) to decimetres, rounded half away from zero.
static func _dm(v: int) -> int:
	return (v + 5) / 10 if v >= 0 else (v - 5) / 10


static func _dm_arr(a: Array) -> Array:
	var out: Array = []
	for v in a:
		out.append(_dm(int(v)))
	return out


## The baked record as written (centimetres: the overworld view redraws the very same town from it).
static func baked(r: int) -> Dictionary:
	_sync()
	var key := str(CData.REGIONS[r]["key"])
	return (_data[key] as Dictionary) if _data.has(key) else {}


static func _decode(d: Dictionary) -> Dictionary:
	var o := {}
	o["foot"] = PackedInt32Array(_dm_arr(d["foot"]))
	o["shore"] = PackedInt32Array(_dm_arr(d["shore"]))
	o["mouth0"] = _dm_arr(d["mouth0"])
	o["mouth1"] = _dm_arr(d["mouth1"])
	o["high"] = _dm_arr(d["high"])
	o["sea_dir"] = int(d["sea_dir"])
	var segs: Array = []
	for ln in d["lines"]:
		var pl: Array = _dm_arr(ln)
		for i in range(0, pl.size() - 2, 2):
			segs.append([int(pl[i]), int(pl[i + 1]), int(pl[i + 2]), int(pl[i + 3])])
	o["streets"] = segs
	var lines: Array = []
	for ln in d["lines"]:
		lines.append(_dm_arr(ln))
	o["lines"] = lines
	o["plaza"] = [-65, -65, 130, 130]
	var lots: Array = []
	for lt in d["lots"]:
		var l: Array = lt
		lots.append([_dm(int(l[0])), _dm(int(l[1])), int(l[2]), int(l[3]), int(l[4]), int(l[5])])
	o["lots"] = lots
	o["steep"] = d["steep"]
	var coast := PackedByteArray()
	coast.resize(COAST_N * COAST_N)
	var bits := Marshalls.base64_to_raw(str(d["coast"]))
	for i in COAST_N * COAST_N:
		coast[i] = (bits[i >> 3] >> (i & 7)) & 1
	o["coast"] = coast
	o["shore_n"] = d["shore_n"]
	o["cdir"] = d["cdir"]
	o["up"] = d["up"]
	o["axis"] = d["axis"]
	o["church_dir"] = d["church_dir"]
	o["near_sea"] = d["near_sea"]
	o["hill"] = d["hill"]
	o["cdist"] = _dm(int(d["cdist"])) if int(d["cdist"]) >= 0 else -1
	o["church"] = _dm_arr(d["church"])
	o["p0"] = _dm_arr(d["p0"])
	o["wc"] = d["wc"]
	return o


# ------------------------------------------------------------------ integer helpers

## Octant of direction (x east, y south) counted anticlockwise on the screen from east: 0..7.
static func _oct(x: int, y: int) -> int:
	var ex := x
	var ny := -y
	var ax := absi(ex)
	var ay := absi(ny)
	if ay * 1000 < ax * 414:
		return 0 if ex > 0 else 4
	if ax * 1000 < ay * 414:
		return 2 if ny > 0 else 6
	if ex > 0:
		return 1 if ny > 0 else 7
	return 3 if ny > 0 else 5


## The yaw whose front (south at yaw 0) faces direction (x, y): the overworld's convention.
static func yaw_facing(x: int, y: int) -> int:
	return (_oct(x, y) + 2) & 7


## Wall-like pieces (long along local x): 0..3.
static func yaw_along(x: int, y: int) -> int:
	return _oct(x, y) & 3


static func yaw4(k: int) -> int:
	return (((k + 1) >> 1) * 2) & 7


static func _dot_pm(x: int, y: int, ux: int, uy: int, uscale: int) -> int:
	## The cosine of the angle between (x, y) and the unit vector (ux, uy) / uscale, per mille.
	var l := FixedMath.isqrt(x * x + y * y)
	if l == 0:
		return 0
	return (x * ux + y * uy) * 1000 / (l * uscale)


## The footprint (flat [x,y,...], dm) at the level scale sc (per mille) times `share` (per mille): the full size
## towards the harbour, `sc` elsewhere (the overworld's rule).
static func scaled(poly: PackedInt32Array, s: Dictionary, sc: int, share: int) -> Array:
	var out: Array = []
	var cd: Array = s["cdir"]
	var sea := int(s["near_sea"]) == 1 and (int(cd[0]) != 0 or int(cd[1]) != 0)
	for i in range(0, poly.size(), 2):
		var x := poly[i]
		var y := poly[i + 1]
		var lv := 1000
		if sc < 999 and sea:
			var w := clampi(_dot_pm(x, y, int(cd[0]), int(cd[1]), 10000), 0, 1000)
			var w2 := w * w / 1000
			lv = 1000 + (1000 * 1000 / sc - 1000) * w2 / 1000
		var f := sc * lv / 1000 * share / 1000
		out.append(x * f / 1000)
		out.append(y * f / 1000)
	return out


# ------------------------------------------------------------------ what the state shows

## Kit style of the town in the state: "town" (colonial), "native", "maya", "haven" or "roman".
static func kind_of(st: Dictionary, r: int) -> String:
	if CData.pack == "west":
		if CSea.haven(st, r):
			return "haven"
		if CState.owner_culture(st, r) == MapGen.CUL_CELTIC:
			return "maya" if str(CData.REGIONS[r]["key"]) == "tayasal" else "native"
		return "town"
	return "roman"


## What of the state a town shows: level, walls, style, port, shipyard and market levels, a recent sack (1 fresh,
## 2, 3 fading, 0 none), the besieging faction (-1 none).
static func facts(st: Dictionary, r: int) -> Dictionary:
	var west := CData.pack == "west"
	var port := false
	var yard := 0
	var kind := kind_of(st, r)
	if west and CData.ships_on():
		port = kind == "haven" or CFleet.harbour(r) >= 0
		yard = CState.building(st, r, CData.SHIPYARD)
	var rs: Dictionary = st["regions"][r]
	var sack := 0
	if rs.has("sacked"):
		var age := int(st["turn"]) - int(rs["sacked"])
		sack = 1 if age < 3 else (2 if age < 6 else (3 if age < 8 else 0))
	var sg := CState.siege_at(st, r)
	return {"lvl": clampi(int(rs["level"]), 0, 2), "walls": CState.walls(st, r), "style": kind, "port": port, "yard": yard,
		"market": CState.building(st, r, CData.MARKET), "sack": sack, "siege": int(sg["f"]) if not sg.is_empty() else -1}


## The facts of town r as a viewer remembers it (fog): the owner, level and walls it last saw; the culture
## (style) follows that owner, the rest is unknown and shown as nothing (no yard / market / sack / siege). A
## haven is the pirate owner with a harbour, as in kind_of.
static func facts_known(st: Dictionary, r: int, owner_f: int, lvl: int, walls: int) -> Dictionary:
	var kind := "roman"
	var port := false
	if CData.pack == "west":
		var cul := CData.faction_culture(owner_f) if owner_f >= 0 else CData.region_culture(r)
		if CSea.on(st) and CSea.pirate(owner_f) and CFleet.harbour(r) >= 0:
			kind = "haven"
		elif cul == MapGen.CUL_CELTIC:
			kind = "maya" if str(CData.REGIONS[r]["key"]) == "tayasal" else "native"
		else:
			kind = "town"
		port = (CData.ships_on() and (kind == "haven" or CFleet.harbour(r) >= 0))
	return {"lvl": clampi(lvl, 0, 2), "walls": walls, "style": kind, "port": port, "yard": 0, "market": 0, "sack": 0, "siege": -1}


static func _lm_ok(lm: Dictionary, f: Dictionary) -> bool:
	if int(lm.get("wl", 0)) > int(f["walls"]) or int(lm.get("lv", 0)) > int(f["lvl"]):
		return false
	return not (bool(lm.get("haven", false)) and str(f["style"]) != "haven")


static func _lmk(p: String, x: int, y: int, yaw: int) -> Dictionary:
	var pd: Array = PD.get(p, [0, 0, 0, 0])
	var fort := 1 if FORT_PIECES.has(p) or p == "fort" else 0
	var kind := "prop"
	if p == "seawall":
		kind = "wall"
	elif fort == 1:
		kind = "fort"
	elif CIVIC_PIECES.has(p) or p == "tower_rome":
		kind = "civic"
	return {"p": p, "x": x, "y": y, "yaw": yaw, "w": 2 * int(pd[1]), "d": 2 * int(pd[2]), "h": int(pd[3]), "fort": fort, "kind": kind}


## Index of the shore sample at the harbour mouth's seaward end (which 0) or the other end (1), -1 without a shore.
static func mouth_index(s: Dictionary, which: int) -> int:
	var shore: PackedInt32Array = s["shore"]
	var n := shore.size() / 2
	if n < 3 or int(s["near_sea"]) != 1:
		return -1
	var cd: Array = s["cdir"]
	var sa := shore[0] * int(cd[0]) + shore[1] * int(cd[1])
	var sb := shore[2 * (n - 1)] * int(cd[0]) + shore[2 * (n - 1) + 1] * int(cd[1])
	var far_end := 0 if sa > sb else n - 1
	return far_end if which == 0 else (n - 1 - far_end)


static func _shore_pt(s: Dictionary, i: int) -> Array:
	var shore: PackedInt32Array = s["shore"]
	var sn: Array = s["shore_n"]
	return [shore[2 * i], shore[2 * i + 1], int(sn[3 * i]), int(sn[3 * i + 1])]


static func _landmarks(s: Dictionary, f: Dictionary, rkey: String) -> Array:
	var out: Array = []
	var shore: PackedInt32Array = s["shore"]
	var n := shore.size() / 2
	var have_shore := int(s["near_sea"]) == 1 and n >= 3
	var cd: Array = s["cdir"]
	var mid := n / 2
	var placed_fort := false
	var lms: Array = LM.get(rkey, []) as Array
	for lm in lms:
		var d: Dictionary = lm
		if not _lm_ok(d, f):
			continue
		var pn := str(d["p"])
		var at := str(d.get("at", ""))
		if pn == "seawall":
			if have_shore:
				var line: Array = []
				for i in n:
					if absi(i - mid) <= 3:
						continue
					var sp := _shore_pt(s, i)
					line.append(int(sp[0]) - int(sp[2]) * 20 / 1000)
					line.append(int(sp[1]) - int(sp[3]) * 20 / 1000)
				var m := _shore_pt(s, mid)
				var e := _lmk("seawall", int(m[0]), int(m[1]), yaw_along(-int(m[3]), int(m[2])))
				e["w"] = 80 * (n - 7)
				e["d"] = 40
				e["h"] = 80
				e["line"] = line
				out.append(e)
				placed_fort = true
			continue
		match at:
			"mouth0", "mouth1":
				var mi := mouth_index(s, 0 if at == "mouth0" else 1)
				if mi >= 0:
					var sp2 := _shore_pt(s, mi)
					var inset := int(d.get("in", 40))
					var x := int(sp2[0]) - int(sp2[2]) * inset / 1000
					var y := int(sp2[1]) - int(sp2[3]) * inset / 1000
					var yw := yaw_facing(-int(sp2[2]), -int(sp2[3])) if str(d.get("face", "")) == "land" else 0
					var e1 := _lmk(pn, x, y, yw)
					if bool(d.get("fort", false)):
						e1["hf"] = 1
					out.append(e1)
					placed_fort = placed_fort or bool(d.get("fort", false))
			"high":
				var hp: Array = s["high"]
				if hp.size() == 2:
					var e2 := _lmk(pn, int(hp[0]), int(hp[1]), 0)
					if bool(d.get("fort", false)):
						e2["hf"] = 1
					out.append(e2)
			"offshore":
				if have_shore:
					var sp3 := _shore_pt(s, clampi(n - 2, 0, n - 1))
					var e3 := _lmk(pn, int(sp3[0]) + int(sp3[2]) * 240 / 1000, int(sp3[1]) + int(sp3[3]) * 240 / 1000, 0)
					e3["hf"] = 1
					e3["off"] = 1
					out.append(e3)
					placed_fort = true
			"plaza_sea":
				if have_shore:
					var dd := mini(130, int(s["cdist"]) * 45 / 100)
					var qx := int(cd[0]) * dd / 10000
					var qy := int(cd[1]) * dd / 10000
					out.append(_lmk(pn, qx, qy, yaw_facing(-qx, -qy)))
			"waterfront":
				if have_shore:
					var want := int(d.get("n", 3)) + 2 * int(f["lvl"])
					var cnt := 0
					for off in [0, -2, 2, -4, 4, -6, 6, -1, 1, -3, 3]:
						if cnt >= want:
							break
						var sp4 := _shore_pt(s, clampi(mid + int(off), 0, n - 1))
						out.append(_lmk(pn, int(sp4[0]) - int(sp4[2]) * 125 / 1000, int(sp4[1]) - int(sp4[3]) * 125 / 1000, yaw_facing(int(sp4[2]), int(sp4[3]))))
						cnt += 1
			"beach":
				if have_shore:
					var want2 := int(d.get("n", 2))
					var cnt2 := 0
					for off2 in [-5, 5, -3, 3]:
						if cnt2 >= want2:
							break
						var sp5 := _shore_pt(s, clampi(mid + int(off2), 0, n - 1))
						out.append(_lmk(pn, int(sp5[0]) - int(sp5[2]) * 36 / 1000, int(sp5[1]) - int(sp5[3]) * 36 / 1000, yaw_facing(-int(sp5[3]), int(sp5[2]))))
						cnt2 += 1
			"cothon":
				var cx := 0
				var cy := 72
				if have_shore:
					var sp6 := _shore_pt(s, mid)
					cx = int(sp6[0]) - int(sp6[2]) * 160 / 1000
					cy = int(sp6[1]) - int(sp6[3]) * 160 / 1000
				out.append(_lmk(pn, cx, cy, 0))
	# every West port's first fort: a harbour fort on the headland, unless a landmark is the fort
	if str(f["style"]) == "town" and CData.pack == "west" and bool(f["port"]) and int(f["walls"]) >= 1 and not placed_fort and have_shore:
		var mi2 := mouth_index(s, 0)
		if mi2 >= 0:
			var sp7 := _shore_pt(s, mi2)
			var e7 := _lmk("harbour_fort", int(sp7[0]) - int(sp7[2]) * 30 / 1000, int(sp7[1]) - int(sp7[3]) * 30 / 1000, 0)
			e7["hf"] = 2
			out.append(e7)
	# the generic pieces on the high ground of a level 2 town (the overworld's: a colonial town's fort, a Roman
	# town's tower, a haven's skull rock from level 1), unless a landmark stands there
	var hp2: Array = s["high"]
	if hp2.size() == 2 and not _lm_at(lms, "high", f):
		# (14 m from the church, measured in the baked centimetres as the overworld does)
		var bk := baked(int(s["r"])) if s.has("r") else {}
		var hc: Array = bk.get("high", [int(hp2[0]) * 10, int(hp2[1]) * 10])
		var cc: Array = bk.get("church", [int((s["church"] as Array)[0]) * 10, int((s["church"] as Array)[1]) * 10])
		var dx := int(hc[0]) - int(cc[0])
		var dy := int(hc[1]) - int(cc[1])
		var far := dx * dx + dy * dy > 1400 * 1400
		var gp := ""
		match str(f["style"]):
			"town":
				gp = "fort" if int(f["lvl"]) == 2 and far else ""
			"roman":
				gp = "tower_rome" if int(f["lvl"]) == 2 and far else ""
			"haven":
				gp = "skull_rock" if int(f["lvl"]) >= 1 else ""
		if gp != "":
			var eg := _lmk(gp, int(hp2[0]), int(hp2[1]), 0)
			eg["gen"] = 1
			out.append(eg)
	return out


## A landmark of the table stands at `at` in this town (with these facts).
static func _lm_at(lms: Array, at: String, f: Dictionary) -> bool:
	for lm in lms:
		if str((lm as Dictionary).get("at", "")) == at and _lm_ok(lm, f):
			return true
	return false


## True when (x, y) cm (the baked frame) lies inside region r's footprint at size sc per mille, as the overworld
## tests it (TownPlan.inside: the 24 radii, linear between them, the full size towards the harbour).
static func inside_foot(r: int, x: int, y: int, sc: int) -> bool:
	var b := baked(r)
	if b.is_empty():
		return true
	var l := FixedMath.isqrt(x * x + y * y)
	if l == 0:
		return true
	var rad: Array = b["rad"]
	var n := rad.size()
	var a := FixedMath.atan2_a(y, x)
	var fi := a * n
	var i := (fi / 1024) % n
	var t := fi % 1024
	var rr := int(rad[i]) + (int(rad[(i + 1) % n]) - int(rad[i])) * t / 1024
	var lv := 1000
	var cd: Array = b["cdir"]
	if sc < 999 and int(b["near_sea"]) == 1 and (int(cd[0]) != 0 or int(cd[1]) != 0):
		var w := clampi((x * int(cd[0]) + y * int(cd[1])) / l * 1000 / 10000, 0, 1000)
		lv = 1000 + (1000 * 1000 / sc - 1000) * (w * w / 1000) / 1000
	return l * 1000000 <= rr * sc * lv


## The plaza's civic piece with its place.
static func _civic(s: Dictionary, kind: String, lvl: int, rkey: String) -> Dictionary:
	var ch: Array = s["church"]
	var cdv: Array = s["church_dir"]
	var cyaw := yaw4(yaw_facing(int(cdv[0]), int(cdv[1])))
	var name := ""
	var x := int(ch[0])
	var y := int(ch[1])
	var yaw := cyaw
	match kind:
		"town":
			name = "chapel" if lvl == 0 else ("church" if lvl == 1 else "cathedral")
			if rkey == "santo_domingo" and lvl >= 1:
				name = "cathedral"
			elif rkey == "merida" and lvl >= 1:
				name = "twin_cathedral"
			if lvl > 0 and s.has("r"):
				# (the overworld's rule: no church where its place lies outside the town at this size)
				var bc: Array = baked(int(s["r"]))["church"]
				var sc := maxi(LVL_S[lvl], 750)
				if not inside_foot(int(s["r"]), int(bc[0]), int(bc[1]), sc):
					name = ""
		"roman":
			name = "shrine" if lvl == 0 else "temple"
			if rkey == "latium" and lvl >= 1:
				name = "capitol"
			if name == "shrine":
				yaw = 0
		"maya":
			name = "itza_temple" if rkey == "tayasal" else "maya_pyramid"
			x = 0
			y = 0
			yaw = 0
		"native":
			name = "longhouse" if lvl >= 1 else "hut_big"
			x = 0
			y = 0
			var ax: Array = s["axis"]
			yaw = yaw_along(int(ax[0]), int(ax[1])) if lvl >= 1 else 0
		_:
			name = "flagpole"
			x = 40
			y = 20
			yaw = 0
	var e := _lmk(name, x, y, yaw)
	e.erase("fort")
	e.erase("kind")
	return e


static func plan(st: Dictionary, r: int) -> Dictionary:
	var s := site(r)
	if s.is_empty():
		return {}
	var f := facts(st, r)
	var rkey := str(CData.REGIONS[r]["key"])
	var lvl: int = f["lvl"]
	var walls: int = f["walls"]
	var kind: String = f["style"]
	var shore: PackedInt32Array = s["shore"]
	var near_sea := int(s["near_sea"]) == 1
	var harbour := bool(f["port"]) and near_sea and shore.size() >= 6
	var sc: int = LVL_S[lvl]
	if kind == "maya" or kind == "native" or kind == "haven":
		sc = sc * STYLE_S / 1000
	var foot := scaled(s["foot"], s, sc, 1000)
	var wall: Array = []
	var gates: Array = []
	var wall_open := 0
	var west_port := CData.pack == "west" and kind == "town" and harbour and rkey != "campeche"
	if walls > 0 and not (west_port and walls == 1):
		var thr := 300 if west_port and walls == 2 else 780
		var full := scaled(PackedInt32Array(foot), s, sc, WALL_S)
		var cd: Array = s["cdir"]
		for i in range(0, full.size(), 2):
			var x: int = full[i]
			var y: int = full[i + 1]
			if harbour and _dot_pm(x, y, int(cd[0]), int(cd[1]), 10000) > thr:
				wall_open = 1
				continue
			wall.append(x)
			wall.append(y)
		# the gate: where the main street's far end leaves the town, on the land side
		var lines: Array = s["lines"]
		var main: Array = lines[0] if lines.size() > 0 else []
		if main.size() >= 4:
			var best := -1000000
			var gx := 0
			var gy := 0
			for e in [[int(main[0]), int(main[1])], [int(main[main.size() - 2]), int(main[main.size() - 1])]]:
				var l := FixedMath.isqrt(int(e[0]) * int(e[0]) + int(e[1]) * int(e[1]))
				var sco := l
				if harbour and l > 0:
					sco -= 1667 * maxi(0, _dot_pm(int(e[0]), int(e[1]), int(cd[0]), int(cd[1]), 10000)) / 1000
				if sco > best:
					best = sco
					gx = int(e[0])
					gy = int(e[1])
			var g := _ray_hit(full, gx, gy)
			if not g.is_empty():
				gates.append([int(g[0]), int(g[1]), yaw_facing(gx, gy)])
	var lms := _landmarks(s, f, rkey)
	return {"kind": kind, "level": lvl, "walls": walls, "harbour": 1 if harbour else 0, "shipyard": 1 if int(f["yard"]) > 0 else 0,
		"owner": int(st["regions"][r]["owner"]), "scale": sc, "foot": foot, "wall": wall, "wall_open": wall_open, "gates": gates,
		"landmarks": lms, "civic": _civic(s, kind, lvl, rkey),
		"port": 1 if bool(f["port"]) else 0, "yard": int(f["yard"]), "market": int(f["market"]), "sack": int(f["sack"]), "siege": int(f["siege"])}


## Where the ray from the origin along (dx, dy) crosses the closed polygon (flat [x,y,...]); [] when it misses.
static func _ray_hit(poly: Array, dx: int, dy: int) -> Array:
	var n := poly.size() / 2
	if n < 3 or (dx == 0 and dy == 0):
		return []
	for i in n:
		var ax: int = poly[2 * i]
		var ay: int = poly[2 * i + 1]
		var bx: int = poly[2 * ((i + 1) % n)]
		var by: int = poly[2 * ((i + 1) % n) + 1]
		var ex := bx - ax
		var ey := by - ay
		var den := dx * ey - dy * ex
		if den == 0:
			continue
		var tn := ax * ey - ay * ex          # t = tn / den along the ray
		var un := ax * dy - ay * dx          # u = un / den along the edge
		if den < 0:
			den = -den
			tn = -tn
			un = -un
		if tn > 0 and un >= 0 and un <= den:
			return [dx * tn / den, dy * tn / den]
	return []


## True when (x, y) lies inside the closed polygon (flat ints), integer ray casting.
static func inside_poly(poly: Array, x: int, y: int) -> bool:
	var n := poly.size() / 2
	var inside := false
	var j := n - 1
	for i in n:
		var xi: int = poly[2 * i]
		var yi: int = poly[2 * i + 1]
		var xj: int = poly[2 * j]
		var yj: int = poly[2 * j + 1]
		if (yi > y) != (yj > y):
			var lhs := x * (yj - yi)
			var rhs := (xj - xi) * (y - yi) + xi * (yj - yi)
			if (yj > yi and lhs < rhs) or (yj < yi and lhs > rhs):
				inside = not inside
		j = i
	return inside


# ------------------------------------------------------------------ the battle map's plan

## The front of a piece at overworld yaw k (0..7: 0 south, turning anticlockwise on the map), unit vector, 1/10000.
const YAW_V := [[0, 10000], [7071, 7071], [10000, 0], [7071, -7071], [0, -10000], [-7071, -7071], [-10000, 0], [-7071, 7071]]


## The main street's far end (dm, the town frame) and whether there is one: where the overworld's gate stands
## (plan()'s rule: the end farther out, a harbour's seaward end counted down).
static func _main_end(s: Dictionary, harbour: bool) -> Array:
	var lines: Array = s["lines"]
	var main: Array = lines[0] if lines.size() > 0 else []
	if main.size() < 4:
		return []
	var cd: Array = s["cdir"]
	var best := -1000000
	var out: Array = []
	for e in [[int(main[0]), int(main[1])], [int(main[main.size() - 2]), int(main[main.size() - 1])]]:
		var l := FixedMath.isqrt(int(e[0]) * int(e[0]) + int(e[1]) * int(e[1]))
		var sco := l
		if harbour and l > 0:
			sco -= 1667 * maxi(0, _dot_pm(int(e[0]), int(e[1]), int(cd[0]), int(cd[1]), 10000)) / 1000
		if sco > best:
			best = sco
			out = [int(e[0]), int(e[1])]
	return out


## The settlement battle's town plan (campaign/cbattle.gd puts it in the city dictionary as "tp"; sim/mapgen.gd
## builds the battle map from it): plan(st, r) and the site's shape turned into the battle map's canonical frame
## (the sea, or an inland town's back, up (-y); the land side where the attackers come down (+y), at the main
## street's far end; x to the right), decimetres, origin the plaza. The map scales it to battle size by level
## (MapGen.tp_scale); landmark pieces keep their own size. {} without a baked site. Keys:
##   v 1, kind, level, walls, coast (1: a port on the sea: the shore is the battle's), harbour, up [ux, uy] (the
##   frame's up in the town frame, 1/10000), foot / wall [x, y, ...], shore [x, y, ...] ([] inland; ordered along
##   x), lines [[x, y, ...], ...] (street polylines, the main street first), ring (the ring road's, level 1 up),
##   lots [[x, y, size, hh, burn], ...],
##   high / mouth0 / mouth1 [x, y] or [], gates [[x, y, face], ...], landmarks [{p, x, y, face, kind, fort, hf,
##   off, gen, w, d, h, line}], civic {p, x, y, face, w, d, h}; face: the piece's front, an angle 0..1023 in the
##   map's convention (FixedMath.atan2_a(dy, dx), y down). Integers only (the city dictionary's rule): kind is an
##   index of MapGen.TP_KINDS, a landmark's kind of MapGen.TP_LKINDS, p of MapGen.TP_NAMES (-1: none).
static func battle_plan(st: Dictionary, r: int) -> Dictionary:
	var p := plan(st, r)
	if p.is_empty():
		return {}
	var s := site(r)
	var shore: PackedInt32Array = s["shore"]
	var near_sea := int(s["near_sea"]) == 1 and shore.size() >= 6
	var coast := near_sea and CData.is_port(r)
	var cd: Array = s["cdir"]
	var ux := 0
	var uy := -10000
	if coast and (int(cd[0]) != 0 or int(cd[1]) != 0):
		ux = int(cd[0])
		uy = int(cd[1])
	else:
		var me := _main_end(s, false)
		if not me.is_empty():
			var l := FixedMath.isqrt(int(me[0]) * int(me[0]) + int(me[1]) * int(me[1]))
			if l > 0:
				ux = -int(me[0]) * 10000 / l
				uy = -int(me[1]) * 10000 / l
	var rot := func(x: int, y: int) -> Array:
		return [(x * -uy + y * ux) / 10000, -(x * ux + y * uy) / 10000]
	var rot_flat := func(a: Array) -> Array:
		var o: Array = []
		for i in range(0, a.size() - 1, 2):
			o.append_array(rot.call(int(a[i]), int(a[i + 1])))
		return o
	var face := func(yk: int) -> int:
		var v: Array = YAW_V[yk & 7]
		var q: Array = rot.call(int(v[0]), int(v[1]))
		return FixedMath.atan2_a(int(q[1]), int(q[0]))
	var pt := func(a: Array) -> Array:
		return rot.call(int(a[0]), int(a[1])) if a.size() == 2 else []
	var sh: Array = []
	if coast:
		sh = rot_flat.call(Array(shore))
		# (ordered along x, west to east)
		if sh.size() >= 4 and int(sh[0]) > int(sh[sh.size() - 2]):
			var rv: Array = []
			for i in range(sh.size() - 2, -1, -2):
				rv.append(int(sh[i]))
				rv.append(int(sh[i + 1]))
			sh = rv
	var lines: Array = []
	for ln in s["lines"]:
		lines.append(rot_flat.call(ln))
	# (the ring road of a colonial or Roman town from level 1, as the overworld draws it)
	var ring: Array = []
	var bk := baked(r)
	if int(p["level"]) >= 1 and (str(p["kind"]) == "town" or str(p["kind"]) == "roman") and bk.has("ring_road"):
		for ln2 in bk["ring_road"]:
			ring.append(rot_flat.call(_dm_arr(ln2)))
	var lots: Array = []
	for lt in s["lots"]:
		var la: Array = lt
		var q2: Array = rot.call(int(la[0]), int(la[1]))
		lots.append([int(q2[0]), int(q2[1]), int(la[3]), int(la[4]), int(la[5])])
	var gates: Array = []
	for g in p["gates"]:
		var ga: Array = g
		var q3: Array = rot.call(int(ga[0]), int(ga[1]))
		gates.append([int(q3[0]), int(q3[1]), face.call(int(ga[2]))])
	var lms: Array = []
	for lm in p["landmarks"]:
		var d: Dictionary = lm
		var q4: Array = rot.call(int(d["x"]), int(d["y"]))
		var e := {"p": MapGen.tp_index(str(d["p"])), "x": int(q4[0]), "y": int(q4[1]), "face": face.call(int(d["yaw"])),
			"kind": MapGen.TP_LKINDS.find(str(d["kind"])),
			"fort": int(d["fort"]), "hf": int(d.get("hf", 0)), "off": int(d.get("off", 0)), "gen": int(d.get("gen", 0)),
			"w": int(d["w"]), "d": int(d["d"]), "h": int(d["h"])}
		if d.has("line"):
			e["line"] = rot_flat.call(d["line"])
		lms.append(e)
	var cv: Dictionary = p["civic"]
	var q5: Array = rot.call(int(cv["x"]), int(cv["y"]))
	var civic := {"p": MapGen.tp_index(str(cv["p"])), "x": int(q5[0]), "y": int(q5[1]), "face": face.call(int(cv["yaw"])),
		"w": int(cv["w"]), "d": int(cv["d"]), "h": int(cv["h"])}
	return {"v": 1, "kind": MapGen.TP_KINDS.find(str(p["kind"])), "level": int(p["level"]), "walls": int(p["walls"]), "coast": 1 if coast else 0,
		"harbour": int(p["harbour"]), "up": [ux, uy], "foot": rot_flat.call(p["foot"]), "wall": rot_flat.call(p["wall"]),
		"shore": sh, "lines": lines, "ring": ring, "lots": lots, "high": pt.call(s["high"]), "mouth0": pt.call(s["mouth0"]),
		"mouth1": pt.call(s["mouth1"]), "gates": gates, "landmarks": lms, "civic": civic}
