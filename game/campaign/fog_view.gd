extends RefCounted
## Fog of war, the view's side (docs/DESIGN.md "Fog of war"). What the local planner's team sees this turn
## (campaign/csight.gd, a pure function of the state) is computed here once per sight change (a new state, another
## planner, the fog toggle: `update`), never per tap or per frame, and every drawing / list asks these helpers.
## `gen` rises whenever anything changed, so a consumer can cache against it. Fog off (the state's "fog" key 0,
## `all_seeing`, a pack without the grid, no planner): every helper says "seen" and `on` is false.
##
## The one place that names the rules' module is CSightImpl (the contract: visible, region_visible, known_owner,
## known_turn, markers, army_visible, fleet_visible, char_visible, battle_visible).
const CSightImpl := preload("res://campaign/csight.gd")
const CState := preload("res://campaign/cstate.gd")
const CData := preload("res://campaign/cdata.gd")
const CGrid := preload("res://campaign/cgrid.gd")
const CFleet := preload("res://campaign/cfleet.gd")

static var all_seeing := false      # testing aid --all-seeing
static var on := false              # fog applies to the planner shown
static var f := -1                  # the planner the sight is for
static var gen := 0
static var vis := PackedByteArray() # per grid cell, 1 = in sight
static var rvis := PackedByteArray()  # per region, 1 = any cell in sight
static var own := PackedInt32Array()  # per region: owner as last seen (-1 never seen)
static var seen_turn := PackedInt32Array()   # per region: the turn of the last look (-1)
static var marks: Array = []        # last-seen army / fleet markers outside sight
static var _cur: Dictionary = {}
static var _sig: Array = []
static var _army_vis := {}          # army id -> bool (the rules' army_visible, for the armies of the state)
static var _fleet_vis := {}
static var _battle_vis := {}


## Is fog applied to state st for planner pf? (The state's "fog" key, default on.)
static func enabled(st: Dictionary, pf: int) -> bool:
	return not all_seeing and pf >= 0 and not st.is_empty() and CState.grid_on(st) and CSightImpl.on(st) and CSightImpl.fog_setting(st) != 0


## Recompute the sight when the state (identity and a few counts), the planner or the fog setting changed.
## Returns true when it did.
static func update(st: Dictionary, pf: int) -> bool:
	var en := enabled(st, pf)
	var sig := [pf, en, int(st.get("turn", -1)), str(st.get("phase", "")), (st.get("armies", []) as Array).size(),
		(st.get("fleets", []) as Array).size(), (st.get("battles", []) as Array).size(), CData.pack, _where(st)]
	if is_same(st, _cur) and sig == _sig:
		return false
	_cur = st
	_sig = sig
	gen += 1
	on = en
	f = pf
	_army_vis = {}
	_fleet_vis = {}
	_battle_vis = {}
	marks = []
	if not en:
		vis = PackedByteArray()
		rvis = PackedByteArray()
		own = PackedInt32Array()
		seen_turn = PackedInt32Array()
		return true
	vis = CSightImpl.visible(st, pf)
	var n := CData.region_count()
	rvis.resize(n)
	own.resize(n)
	seen_turn.resize(n)
	for r in n:
		rvis[r] = 1 if CSightImpl.region_visible(st, pf, r, vis) else 0
		own[r] = CSightImpl.known_owner(st, pf, r, vis)
		seen_turn[r] = CSightImpl.known_turn(st, pf, r, vis)
	marks = CSightImpl.markers(st, pf, vis)
	var armies: Array = st.get("armies", [])
	for i in armies.size():
		_army_vis[int(armies[i]["id"])] = CSightImpl.army_visible(st, pf, i, vis)
	var fleets: Array = st.get("fleets", [])
	for i in fleets.size():
		_fleet_vis[int(fleets[i]["id"])] = CSightImpl.fleet_visible(st, pf, i, vis)
	for b in st.get("battles", []):
		_battle_vis[int(b["id"])] = CSightImpl.battle_visible(st, pf, int(b["id"]), vis)
	return true


## A cheap sum of where the armies and fleets stand and who owns what (a state changed in place, as the input tests
## do, is caught by it; ~250 additions).
static func _where(st: Dictionary) -> int:
	var h := 0
	for a in st.get("armies", []):
		h = (h * 31 + int(a.get("x", 0)) * 7 + int(a.get("y", 0)) + int(a["f"])) & 0xFFFFFFF
	for fl in st.get("fleets", []):
		h = (h * 31 + int(fl.get("x", 0)) * 7 + int(fl.get("y", 0))) & 0xFFFFFFF
	for rg in st.get("regions", []):
		h = (h * 31 + int(rg["owner"]) + 1) & 0xFFFFFFF
	return h


static func cell_seen(c: int) -> bool:
	return not on or c < 0 or c >= vis.size() or vis[c] != 0


static func region_seen(r: int) -> bool:
	return not on or r < 0 or r >= rvis.size() or rvis[r] != 0


## Region r was never seen by the planner's team (grey, no borders).
static func never(r: int) -> bool:
	return on and r >= 0 and r < rvis.size() and rvis[r] == 0 and seen_turn[r] < 0


## The owner of region r as the planner knows it: the real one in sight, else the last seen (-1 never).
static func shown_owner(st: Dictionary, r: int) -> int:
	if not on or r >= rvis.size() or rvis[r] != 0:
		return CState.owner(st, r)
	return own[r]


## The turn region r was last looked at (-1 never), or the current turn in sight.
static func last_seen(st: Dictionary, r: int) -> int:
	if not on or r >= rvis.size() or rvis[r] != 0:
		return int(st.get("turn", 0))
	return seen_turn[r]


static func _mine(st: Dictionary, g: int) -> bool:
	return g == f or CState.team(st, g) == CState.team(st, f)


## May the planner see army a? (The rules' answer for the armies of the state; the cell in sight for one only the
## preview has.)
static func army_seen(st: Dictionary, a: Dictionary) -> bool:
	if not on:
		return true
	var id := int(a["id"])
	if _army_vis.has(id):
		return bool(_army_vis[id])
	return _mine(st, int(a["f"])) or cell_seen(CState.cell(a))


static func fleet_seen(st: Dictionary, fl: Dictionary) -> bool:
	if not on:
		return true
	var id := int(fl["id"])
	if _fleet_vis.has(id):
		return bool(_fleet_vis[id])
	return _mine(st, int(fl["f"])) or cell_seen(CFleet.cell(fl))


static func battle_seen(_s: Dictionary, b: Dictionary) -> bool:
	if not on:
		return true
	var id := int(b["id"])
	if _battle_vis.has(id):
		return bool(_battle_vis[id])
	return region_seen(int(b["r"]))


## Last-seen marker at cell c (or {}), for a tap on the map.
static func marker_at(c: int) -> Dictionary:
	for m in marks:
		if int(m["cell"]) == c:
			return m
	return {}


## May the planner be told of event e (chronicle, turn summary)? CSight.event_seen: its own team's, world news, or
## a place looked at since.
static func event_seen(st: Dictionary, e: Dictionary) -> bool:
	return not on or CSightImpl.event_seen(st, f, e, vis)
