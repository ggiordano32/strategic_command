extends Node2D
## Campaign map, screen layer: settlements (size by level, a wall ring with
## towers per wall level, a white star for the key cities), names, pending battles, sieges (a ring of
## tents round the settlement in the besieger's colour), army markers
## (faction colour, unit count, strength bar; a small tower: inside the
## walls), planned moves as arrows (red an assault, orange a siege; state
## version 5: the path, solid this turn, dotted after), and hit tests for
## taps. Positions come from map_geo.gd through `xform` (map
## pixels -> screen), set by the campaign screen every frame.
##
## State version 6 (the continuous overworld, CState.grid_on): settlements
## stand on their grid cell and armies on theirs (several on one cell side
## by side; armies inside the walls under their settlement), pending battles
## on their cell; planned paths run along cell centres (solid this turn,
## dashed beyond, a ring where this turn ends, the intent at the end:
## swords an attack or assault, a tent a siege, a plus a merge, a tower
## going inside; a plain march has no end badge);
## for the selected army the enemies' zones of control (red circles) and
## its support (yellow) and attack (red) lines; during a turn replay armies
## slide along their step log (replay_pos) and battles pop up (markers).
## A pack with ships (N2): a blockaded port has a dashed ring in the
## blockader's colour round its harbour; the flota's ships carry a gold
## treasure mark and its course (to the meeting port, then off the map) is
## a dashed gold line to a "To Spain" arrow at the exit.
## N2b: hurricanes are grey swirls turning on the sea (their radius) with
## their past track dotted and the forecast cone (where next turn's move
## sweeps) in orange; sunk treasure ships leave a wreck (a mast out of the
## water, a gold dot, the galleon's name zoomed in); pirate fleets carry
## their captain's name under the ship.

const ZProf := preload("res://game/campaign/zprof.gd")
const CData := preload("res://campaign/cdata.gd")
const FactionEmblem := preload("res://game/faction_emblem.gd")
const CState := preload("res://campaign/cstate.gd")
const FogView := preload("res://game/campaign/fog_view.gd")
const Geo := preload("res://game/campaign/map_geo.gd")
const CGrid := preload("res://campaign/cgrid.gd")
const CRules := preload("res://campaign/crules.gd")
const CDip := preload("res://campaign/cdip.gd")
const CFleet := preload("res://campaign/cfleet.gd")
const CSea := preload("res://campaign/csea.gd")
const CStorm := preload("res://campaign/cstorm.gd")
const CLanes := preload("res://campaign/clanes.gd")
const CCaptain := preload("res://campaign/ccaptain.gd")
const SeaWaves := preload("res://game/campaign/sea_waves.gd")
const MapView := preload("res://game/campaign/map_view.gd")
const Minis := preload("res://game/campaign/minis_layer.gd")  # miniatures replace the icons / hulls when Minis.on_*
const MenuStyle := preload("res://game/menu/menu_style.gd")
const OvBatch := preload("res://game/campaign/ov_batch.gd")
const InkLines := preload("res://game/campaign/ink_lines.gd")
const LaneTraders := preload("res://game/campaign/lane_traders.gd")

const ARMY_W := 30.0
const ARMY_H := 26.0
const ARMY_GAP := 4.0
const SITE_R := [5.0, 7.0, 9.5]
const SITE_HIT := 22.0      # px: a settlement's tap radius round its anchor (touch-sized; was 16)
const FONT := 13
const DIORAMA_ZOOM := 1.6   # from this zoom the city names are 18 px or more and use the display face

## The drawing style, shared with the map key (map_key.gd draws its samples
## with the same static painters below, so the key cannot drift from the
## map). Path colours by CRules.move_aim kind.
const COL_MOVE := Color(0.95, 0.95, 0.9)
const COL_ATTACK := Color(1.0, 0.45, 0.35)       # attack, assault, relief, sally
const COL_SIEGE := Color(1.0, 0.7, 0.25)         # siege, join a siege
const COL_MERGE := Color(0.55, 0.95, 0.6)
const COL_TRESPASS := Color(1.0, 0.55, 0.1)      # a march into, or an army standing in, the land of a faction at peace
const COL_MERGE_NO := Color(0.7, 0.7, 0.68)      # too many units to merge
const ATTACK_KINDS: Array[String] = ["attack", "assault", "relief", "sally"]
const SIEGE_KINDS: Array[String] = ["siege", "join"]
const PATH_W_NOW := 4.0      # this turn: solid
const PATH_W_LATER := 3.0    # later turns: dashed
const PATH_DASH := 8.0
const PATH5_DASH := 9.0      # version 5: dotted hops
const COL_SUPPORT := Color(1.0, 0.85, 0.2, 0.9)  # link 0: supports / supported by
const COL_THREAT := Color(1.0, 0.25, 0.2, 0.9)   # link 1: an enemy it can attack
const LINK_W := 3.0
const LINK_DASH := 10.0
const ZONE_FILL := Color(0.85, 0.15, 0.1, 0.12)
const ZONE_EDGE := Color(1.0, 0.35, 0.25, 0.85)
const COL_BATTLE := Color(0.75, 0.1, 0.08)
const COL_KEY_CITY := Color(1, 1, 1)
const COL_SELECTED := Color(1, 0.95, 0.4, 0.95)
const COL_MOVED := Color(0.6, 0.6, 0.6)          # versions 1-5: has moved this turn
const COL_OUTLINE := Color(0.05, 0.05, 0.05, 0.95)  # dark edge round faction-coloured marks
const BAR_GOOD := Color(0.5, 1.0, 0.5)           # strength above 60 %
const BAR_LOW := Color(1.0, 0.8, 0.3)
const MERGE_COLS: Array[Color] = [Color(0.3, 0.75, 0.35), Color(0.9, 0.7, 0.2)]
const STANCE_LETTERS := {CData.ST_FORCED: "F", CData.ST_FORTIFY: "D", CData.ST_RAID: "R"}
const STANCE_COLS := {CData.ST_FORCED: Color(0.3, 0.6, 1.0), CData.ST_FORTIFY: Color(0.55, 0.55, 0.5), CData.ST_RAID: Color(0.95, 0.55, 0.15)}

var state: Dictionary = {}
var xform := Transform2D.IDENTITY
var zoom := 1.0
var selected_army := -1
var player := -1
## Planned moves of the player planning now: [[army id, to region], ...].
var moves: Array = []
var attack_moves: Array[int] = []  # army ids whose move is an attack
var siege_moves: Array[int] = []   # ... of which these lay siege (or join one)
## State version 5: planned and stored marches [{army, pts [map points from
## the army's region], now (segments walked this turn)}]: solid this turn,
## dotted after.
var paths: Array = []
var pulse := 0.0
## Version 6: planned paths [{army, pts [map points: the army's cell then
## each step], now (index of the last point reached this turn), kind
## (CRules.move_aim kind)}], also the drag preview (army -1 never: drag
## holds the dragged army's preview, {} none); enemy zones [[map centre,
## radius in map px]]; links [[army id, other id, 0 support | 1 attack]];
## replay_pos {army id: map point} during a replay; markers [[map point,
## seconds left]] (battles popping up).
var grid := false
var paths6: Array = []
var drag: Dictionary = {}
var zones: Array = []
var links: Array = []
var replay_pos := {}
var replay_trail := {}  # army id -> map points passed so far in the replay
var markers: Array = []
## The selected army's merge and gift candidates [[army id, 0 merge | 1 gift
## | 2 too many units]] (a small glyph on the banners of 0 and 1 only: an
## over-full merge shows as its grey path and caption when tapped) and the
## one tapped once (merge_tap: its glyph rings).
var merge_marks: Array = []
var merge_tap := -1
## The army under a dragged army (an Exchange drop): a gold ring on its banner while the drag is over it, -1 none.
var drop_army := -1
var _tips: Array = []  # intents to draw over the banners: [point, kind, colour, caption]
## Fleets (a pack with ships): the selected one and the planned voyages
## ([{fleet, path [cells], t [turn per cell], land, attack}]).
var selected_fleet := -1
var fleet_paths: Array = []
## (Sea lanes, 2026-10-22) The lane ids the selected fleet of ours can raid (drawn thicker: a tap on one orders the raid).
var raid_lanes: Array = []
var _raider_ids := {}   # fleet ids raiding a lane now (the pennant's red "raider" tag)
const LANE_HIT := 16.0   # px: a lane's tap radius
const COL_RAID := Color(1.0, 0.3, 0.22)
const COL_LANE_WAR := Color(0.5, 0.2, 0.14, 0.9)   # a lane between ports at war: no trade
const FLEET_W := 30.0
var sea_reach: Array = []       # the selected fleet's reach this turn: outlines in map pixels
var _sea_reach_fill: Array = []  # ... the outer ones that triangulate
var sea_reach_rt := PackedInt32Array()   # the reach those outlines are of
var landing_cells := PackedInt32Array()   # the beaches a loaded fleet can land on this turn (lit), or where an army boards
var _landing_segs := PackedVector2Array()   # ... their coast as segment pairs (map px)
const COL_LANDING := Color(1.0, 0.92, 0.5)
var board_cells := PackedInt32Array()   # land cells where the selected army may stand to board one of our fleets (teal)
var pickup_cells := PackedInt32Array()   # sea cells where our fleet may lie to take the armies of ours aboard (teal)
const COL_BOARD := Color(0.25, 0.85, 0.8)


## The selected fleet's reach (CFleet.reach: 0 this turn), drawn over the
## water (the map's own reach shading sits under the sea).
func set_sea_reach(rt: PackedInt32Array) -> void:
	if rt == sea_reach_rt and (not rt.is_empty() or sea_reach.is_empty()):
		return   # (the same reach: its outlines are kept)
	sea_reach_rt = rt
	sea_reach = []
	_sea_reach_fill = []
	if rt.size() != CGrid.count():
		return
	var now := PackedByteArray()
	now.resize(rt.size())
	for c in rt.size():
		now[c] = 1 if rt[c] == 0 else 0
	sea_reach = MapView.outline(now)
	for lp in sea_reach:
		if MapView._area(lp) > 0.0 and not Geometry2D.triangulate_polygon(lp).is_empty():
			_sea_reach_fill.append(lp)


## Light the beaches of the selected fleet's landing reach: with one of our fleets selected that carries troops, the
## land_ok beaches beside the sea cells it reaches this turn (sea_reach_rt); with an army of ours selected beside a
## fleet of ours it may board (CFleet.embark_check), the beach it boards from. True when the lit set changed.
func set_landing(st: Dictionary, f: int, fleet: Dictionary, army: Dictionary) -> bool:
	var lit := PackedInt32Array()
	if CFleet.on(st) and f >= 0:
		if not fleet.is_empty() and int(fleet["f"]) == f and not (fleet["carry"] as Array).is_empty() \
				and sea_reach_rt.size() == CGrid.count():
			for c in MapView.beach_cells():
				if not CFleet.land_ok(st, f, c):
					continue
				for k in 8:
					var j := CGrid.at(CGrid.cx(c) + CGrid.DX[k], CGrid.cy(c) + CGrid.DY[k])
					if j >= 0 and sea_reach_rt[j] == 0:
						lit.append(c)
						break
		elif fleet.is_empty() and not army.is_empty() and int(army["f"]) == f:
			var ac := CState.cell(army)
			var r := CGrid.site_region(ac)
			var from := ac if MapView.beach_points(ac).size() > 0 else (CFleet.harbour(r) if r >= 0 else -1)
			if from >= 0 and MapView.beach_points(from).size() > 0:
				for fl in CFleet.fleets_of(st, f):
					if CFleet.embark_check(st, f, int(army["id"]), int(fl["id"])) == "":
						lit.append(from)
						break
	var bc := PackedInt32Array()
	var pc := PackedInt32Array()
	if CFleet.on(st) and f >= 0:
		if fleet.is_empty() and not army.is_empty() and int(army["f"]) == f and int(army["busy"]) == 0 \
				and CRules.siege_role(st, army) == 0:
			var cset := {}
			for fl in CFleet.fleets_of(st, f):
				if CFleet.carried_units(fl) + CState.unit_count(army) <= CFleet.capacity(fl):
					for c in CFleet.boarding_cells(st, fl):
						cset[int(c)] = 1
			var ks := cset.keys()
			ks.sort()
			for c in ks:
				bc.append(int(c))
		elif not fleet.is_empty() and int(fleet["f"]) == f and CFleet.carried_units(fleet) < CFleet.capacity(fleet):
			var set2 := {}
			for a in CState.armies_of(st, f):
				if int(a["busy"]) != 0 or CRules.siege_role(st, a) != 0 or CFleet.near_fleet(a, fleet) \
						or CFleet.carried_units(fleet) + CState.unit_count(a) > CFleet.capacity(fleet):
					continue
				for c in CFleet.pickup_cells(st, a):
					set2[int(c)] = 1
			var ks2 := set2.keys()
			ks2.sort()
			for c in ks2:
				pc.append(int(c))
	var board_changed := bc != board_cells or pc != pickup_cells
	board_cells = bc
	pickup_cells = pc
	if lit == landing_cells:
		return board_changed
	landing_cells = lit
	_landing_segs = PackedVector2Array()
	for c in lit:
		var pts := MapView.beach_points(c)
		if pts.size() == 1:
			_landing_segs.append(pts[0] - Vector2(2, 0))
			_landing_segs.append(pts[0] + Vector2(2, 0))
		for i in pts.size() - 1:
			if pts[i].distance_squared_to(pts[i + 1]) <= 36.0:   # (a gap where the coast leaves the cell and returns)
				_landing_segs.append(pts[i])
				_landing_segs.append(pts[i + 1])
	return true


## Map point (map pixels) of the centre of grid cell c.
static func cell_point(c: int) -> Vector2:
	var px := float(CGrid.cell_px())
	return Vector2((CGrid.cx(c) + 0.5) * px, (CGrid.cy(c) + 0.5) * px)


## The grid cell under map point p (-1 off the grid).
static func cell_of_point(p: Vector2) -> int:
	var px := float(CGrid.cell_px())
	return CGrid.at(int(floor(p.x / px)), int(floor(p.y / px)))


## Where settlement r is drawn (map pixels): its grid cell in version 6.
func site_point(r: int) -> Vector2:
	return cell_point(CGrid.site(r)) if grid else Geo.site(r)


func to_screen(p: Vector2) -> Vector2:
	return xform * p


## Marker scale: full size from zoom 0.7 up, down to half when zoomed out.
func mk() -> float:
	return clampf(zoom / 0.7, 0.5, 1.0)


## Cached shaped text (a TextLine per string and size): the labels are redrawn on every zoom step, and shaping them
## again each time (twice, outline and fill) was most of the overlay's cost.
static var _lines := {}


static func text_line(text: String, fs: int, display: bool = false) -> TextLine:
	var key := "%d|%s|%d" % [fs, text, 1 if display else 0]
	var tl: TextLine = _lines.get(key)
	if tl == null:
		if _lines.size() > 600:
			_lines.clear()
		tl = TextLine.new()
		var f: Font = ThemeDB.fallback_font
		if display and MenuStyle.display_font(true) != null:
			f = MenuStyle.display_font(true)
		tl.add_string(text, f, fs)
		_lines[key] = tl
	return tl


static func text_w(text: String, fs: int, display: bool = false) -> float:
	return text_line(text, fs, display).get_size().x


## draw_string / draw_string_outline at the baseline point `at`, with an outline of width ow (0 none), on a
## CanvasItem or an OvBatch.
static func put(ci, at: Vector2, text: String, fs: int, col: Color, ow := 0, oc := Color(0, 0, 0), display := false) -> void:
	var tl := text_line(text, fs, display)
	var top := at - Vector2(0.0, tl.get_line_ascent())
	if not ci is CanvasItem:
		(ci as OvBatch).text_line(tl, top, col, ow, oc, fs, display)
		return
	var rid := (ci as CanvasItem).get_canvas_item()
	if ow > 0:
		tl.draw_outline(rid, top, ow, oc)
	tl.draw(rid, top, col)


## Screen position of each army marker: {id: Vector2}.
func army_positions() -> Dictionary:
	var out := {}
	if state.is_empty():
		return out
	if grid:
		return _army_positions6()
	var by_region := {}
	for a in state["armies"]:
		var r := int(a["r"])
		if not by_region.has(r):
			by_region[r] = []
		by_region[r].append(a)
	for r in by_region:
		var list: Array = by_region[r]
		var m := mk()
		var c := to_screen(Geo.site(r)) + Vector2(0, (ARMY_H * 0.5 + 12.0) * m)
		var n := list.size()
		var step := (ARMY_W + ARMY_GAP) * m * (0.8 if m < 0.8 else 1.0)
		for k in n:
			var off := (k - (n - 1) * 0.5) * step
			out[int(list[k]["id"])] = c + Vector2(off, 0)
	return out


func army_at(p: Vector2) -> int:
	var pos := army_positions()
	var best := -1
	var best_d := 1e9
	for id in pos:
		var q: Vector2 = pos[id]
		var d := q.distance_to(p)
		var hit := absf(p.x - q.x) <= ARMY_W * 0.5 * mk() + 6.0 and absf(p.y - q.y) <= ARMY_H * 0.5 * mk() + 8.0
		if hit and d < best_d:
			best = int(id)
			best_d = d
	return best


## Screen position of each fleet marker: {id: Vector2} (fleets sharing a
## cell side by side).
func fleet_positions() -> Dictionary:
	var out := {}
	if state.is_empty() or not state.has("fleets"):
		return out
	var groups := {}
	var order: Array = []
	for fl in state["fleets"]:
		if not FogView.fleet_seen(state, fl):
			continue   # (fog: a fleet out of sight is not drawn, nor reachable)
		var c := CFleet.cell(fl)
		if not groups.has(c):
			groups[c] = []
			order.append(c)
		(groups[c] as Array).append(int(fl["id"]))
	var m := mk()
	var port_of := {}   # harbour / dock cell -> region (miniatures: fleets in port stand beside the town)
	if Minis.on_sites:
		for r in CData.region_count():
			for pc in [CFleet.harbour(r), CFleet.dock(r)]:
				if int(pc) >= 0 and not port_of.has(int(pc)):
					port_of[int(pc)] = r
	for c in order:
		var ids: Array = groups[c]
		var base := to_screen(cell_point(int(c)))
		if port_of.has(int(c)):
			var pr: int = port_of[int(c)]
			var side := port_side(pr)
			var spot := Minis.fleet_spot(pr, to_screen(site_point(pr)), side, zoom, to_screen)
			var stp := (FLEET_W + 4.0) * m * 0.8
			for k in ids.size():
				out[int(ids[k])] = spot + Vector2(side * k * stp, 0)
			continue
		for k in ids.size():
			out[int(ids[k])] = base + Vector2((k - (ids.size() - 1) * 0.5) * (FLEET_W + 4.0) * m, 0)
	return out


## Banners at towns (version 6; owner 2026-10-22, reworked 2026-10-23: a garrison stands ON its town, and no army moves
## with the zoom). The rule, in `_army_positions6` / `_garrison_centre` / `_ring_nudge`, one pass in this order:
##   1. a free army (a march, a replay, a field cell, also beside a town) stands on its own cell, side by side with the
##      others of the cell: the same place at every zoom;
##   2. the armies inside a town make one stack, the first banner centred on the settlement's marker (relief style) or
##      its model's footprint centre (table style), the others one banner height further down each (the name is above);
##      the planned path of such an army starts at the settlement's site point;
##   3. a besieger stands on its cell of the ring of the besieged town; when that spot is taken (by the garrison, a tent
##      or another banner) it is pushed along the ring (the same radius, screen pixels: not zoom-stable), then along
##      the rings a banner's height further out, to the nearest free spot wholly on land.
## `banner_reach(r)` is the screen rectangle a garrison's banners touch at least (footprint + 8 px).
var _land_cache := {}       # "tag_k" -> bool: the spot is wholly on land (world-fixed, kept per ~5 % band of zoom)
var _spot_zoom := -99999
const RING_N := 24


func _land_band() -> void:
	var band := int(floor(log(maxf(zoom, 0.01)) * 20.0))
	if band != _spot_zoom:
		_land_cache.clear()
		_spot_zoom = band


## The town's footprint relative to its anchor (screen px): the model's built-up core, or the marker with its wall ring.
func _footprint(r: int) -> Rect2:
	if Minis.on_sites:
		# (the model's rectangle spans its fields and outlying houses: the banners hug the built-up core, 70 % x 85 %)
		var mr := Minis.model_rect(zoom, r)
		var cc := mr.get_center()
		return Rect2(cc - Vector2(mr.size.x * 0.35, mr.size.y * 0.425), Vector2(mr.size.x * 0.7, mr.size.y * 0.85))
	var m := mk()
	var rad := _site_rad(r) + (3.0 + 1.2 * CState.walls(state, r)) * m + 2.5
	return Rect2(-rad, -rad, rad * 2.0, rad * 2.0)


## Radius of settlement r's marker (screen px).
func _site_rad(r: int) -> float:
	var lvl := clampi(int(state["regions"][r]["level"]), 0, 2)
	return maxf(SITE_R[lvl] * mk(), 4.5 + 1.5 * lvl)


## The screen rectangle a garrison's banners touch at least: the town's footprint and a margin of 8 px (the banners
## stand on a ring just outside the footprint).
func banner_reach(r: int) -> Rect2:
	var fp := _footprint(r)
	return Rect2(to_screen(site_point(r)) + fp.position, fp.size).grow(8.0)


## The siege ring's radius round town r on screen (the dashed ring `_sites_body` draws).
func siege_ring_radius(r: int) -> float:
	var m := mk()
	var sr := _site_rad(r) + (6.0 + 1.2 * CState.walls(state, r)) * m
	if grid:
		sr = maxf(sr, CGrid.cell_px() * 1.1 * zoom)
	return sr


## The rectangle of a stack of n banners whose first one is centred at c (stack: one under the other; else side by side).
func _group_rect(c: Vector2, n: int, stack: bool, m: float) -> Rect2:
	var hw := ARMY_W * 0.5 * m
	var hh := ARMY_H * 0.5 * m
	if stack:
		return Rect2(c.x - hw, c.y - hh, hw * 2.0, hh * 2.0 + (n - 1) * (ARMY_H * m * 0.9 + 3.0))
	var step := (ARMY_W + ARMY_GAP) * m * (0.8 if m < 0.8 else 1.0)
	var x0 := c.x - (n - 1) * 0.5 * step - hw
	return Rect2(x0, c.y - hh, hw * 2.0 + (n - 1) * step, hh * 2.0)


func _free(rc: Rect2, placed: Array) -> bool:
	var g := rc.grow(1.5)
	for o in placed:
		if g.intersects(o):
			return false
	return true


## The tents of the sieges in sight as rectangles (`draw_siege_ring` puts five on the upper half of the ring).
func _tent_rects() -> Array:
	var out: Array = []
	var m := mk()
	var ts := 5.5 * m
	for sg in state.get("sieges", []):
		var r := int(sg["r"])
		if not FogView.region_seen(r):
			continue
		var p := to_screen(site_point(r))
		var rr := siege_ring_radius(r) + 6.0 * m
		for k in 5:
			var a := PI + PI * (k + 0.5) / 5
			var c := p + Vector2(cos(a), sin(a)) * rr
			out.append(Rect2(c - Vector2(ts, ts), Vector2(ts, ts) * 2.0))
	return out


## Where a garrison's stack stands (2026-10-23): the first banner centred on the settlement's marker (relief style) or
## on its model's footprint centre (table style).
func _garrison_centre(r: int) -> Vector2:
	var fp := _footprint(r)
	return to_screen(site_point(r)) + fp.position + fp.size * 0.5


## A besieger's group at screen point c (n banners side by side) round town r: the cell's spot when free, else the
## nearest free spot on the same ring, wholly on land (alternating sides, 12 steps each way), then on the rings
## outside it (a banner's height further out each, three of them).
func _ring_nudge(c: Vector2, n: int, r: int, key: String, placed: Array, m: float) -> Vector2:
	_land_band()
	if _free(_group_rect(c, n, false, m), placed):
		return c
	var site := to_screen(site_point(r))
	var d := c - site
	var rad0 := maxf(d.length(), 8.0)
	var ang := d.angle()
	for need_land in [true, false]:   # (a narrow spit or an islet: then a banner may stand over the water, never over another)
		for j in 4:
			var rad := rad0 + j * (ARMY_H * m * 0.9 + 2.0)
			var step := (ARMY_W * m * maxf(n, 1) + ARMY_GAP + 4.0) / rad
			for k in range(0 if j > 0 else 1, 13):
				for sgn in ([1.0, -1.0] if k > 0 else [1.0]):
					var q: Vector2 = site + Vector2.from_angle(ang + sgn * k * step) * rad
					if not _free(_group_rect(q, n, false, m), placed):
						continue
					if not need_land:
						return q
					var tag := "b%s_%d_%d" % [key, j, int(sgn) * k]
					if not _land_cache.has(tag):
						_land_cache[tag] = _banner_on_land(q, m)
					if _land_cache[tag]:
						return q
	return c


## True when a banner centred at screen point c (marker scale m) stands wholly on land.
func _banner_on_land(c: Vector2, m: float) -> bool:
	var inv := xform.affine_inverse()
	var hx := ARMY_W * 0.5 * m
	var hy := ARMY_H * 0.5 * m
	for d in [Vector2.ZERO, Vector2(-hx, -hy), Vector2(hx, -hy), Vector2(-hx, hy), Vector2(hx, hy)]:
		if Geo.region_at(inv * (c + d)) < 0:
			return false
	return true


## -1 / +1: the side (left / right) of its town where region r's harbour lies.
func port_side(r: int) -> float:
	if Minis.on_sites:
		var ps := Minis.harbour_side(r)
		if ps != 0.0:
			return ps
	var h := CFleet.harbour(r)
	if h < 0:
		h = CFleet.dock(r)
	if h < 0:
		return 1.0
	var dx := cell_point(h).x - site_point(r).x
	return -1.0 if dx < -1.0 else 1.0


## The lane of `ids` (CLanes ids) whose curve passes within LANE_HIT px of screen point p, the nearest (-1 none).
func lane_at(p: Vector2, ids: Array) -> int:
	var best := -1
	var bd := LANE_HIT
	for id in ids:
		var poly := MapView.lane_poly(int(id))
		for i in range(poly.size() - 1):
			var q := Geometry2D.get_closest_point_to_segment(p, xform * poly[i], xform * poly[i + 1])
			var d := q.distance_to(p)
			if d < bd:
				bd = d
				best = int(id)
	return best


func fleet_at(p: Vector2) -> int:
	var pos := fleet_positions()
	var best := -1
	var bd := 1e9
	for id in pos:
		var q: Vector2 = pos[id]
		var d := q.distance_to(p)
		if d <= FLEET_W * 0.6 * mk() + 8.0 and d < bd:
			bd = d
			best = int(id)
	return best


## The settlement whose marker (22 px round its anchor: a touch-sized target; it was 16) or model holds screen point p.
## A tap within 30 % of a cell's width of the centre of a cell next to the town but 16 px or more from the anchor is that
## cell's (a march or a siege camp laid on the ring), not the town's.
func settlement_at(p: Vector2) -> int:
	for r in CData.region_count():
		var q := to_screen(site_point(r))
		var d := q.distance_to(p)
		if d > SITE_HIT:
			continue
		if d > 16.0 and grid:
			var cpx := CGrid.cell_px() * zoom
			var c := cell_of_point(xform.affine_inverse() * p)
			if c >= 0 and c != CGrid.site(r) and CGrid.cheb(c, CGrid.site(r)) == 1 \
					and to_screen(cell_point(c)).distance_to(p) <= cpx * 0.3:
				continue
		return r
	return _town_at(p)


## The modelled town whose footprint (an ellipse over the model's width, from the roof tops to the ground
## below the anchor) holds screen point p; the nearest centre when two overlap (-1 none).
func _town_at(p: Vector2) -> int:
	if not Minis.on_sites:
		return -1
	var best := -1
	var bd := 1e9
	for r in CData.region_count():
		var q := to_screen(site_point(r))
		if absf(p.x - q.x) > 400.0 or absf(p.y - q.y) > 400.0:
			continue
		var mr := Minis.model_rect(zoom, r)
		var cx := q.x + mr.position.x + mr.size.x * 0.5
		var hy := mr.size.y * 0.5
		var cy := q.y + mr.position.y + hy
		var dx := (p.x - cx) / maxf(mr.size.x * 0.5, 1.0)
		var dy := (p.y - cy) / maxf(hy, 1.0)
		var d := dx * dx + dy * dy
		if d <= 1.0 and d < bd:
			bd = d
			best = r
	return best


## Version 6: armies at their cells; armies sharing a cell side by side; the armies of a town (inside its walls or
## standing at its model) one stack beside the town; besiegers on the ring; no two banners overlap (see "Banners at
## towns" above); during a replay at replay_pos.
func _army_positions6() -> Dictionary:
	var out := {}
	var groups := {}
	var order: Array = []
	var m := mk()
	var besieger := {}   # army id -> the region it besieges
	for sg in state.get("sieges", []):
		var sr := int(sg["r"])
		if FogView.region_seen(sr):
			for a in CRules.besiegers(state, sr):
				besieger[int(a["id"])] = sr
	for a in state["armies"]:
		if not FogView.army_seen(state, a):
			continue   # (fog: an army out of sight is not drawn, nor reachable)
		var id := int(a["id"])
		var key := ""
		var c := Vector2.ZERO
		var kind := 0   # 0 free, 1 at a town (a stack), 2 besieging (kind of the ring's town in g[3])
		var town_r := -1
		if replay_pos.has(id):
			c = to_screen(replay_pos[id])
			key = "p%d_%d" % [int(c.x / 6.0), int(c.y / 6.0)]
		elif CRules.inside(state, a):
			town_r = CGrid.site_region(CState.cell(a))
			c = _garrison_centre(town_r)
			key = "s%d" % town_r
			kind = 1
		elif besieger.has(id):
			c = to_screen(cell_point(CState.cell(a)))
			key = "c%d" % CState.cell(a)
			kind = 2
			town_r = besieger[id]
		else:
			c = to_screen(cell_point(CState.cell(a)))
			key = "c%d" % CState.cell(a)
		if not groups.has(key):
			groups[key] = [c, [], kind, town_r]
			order.append(key)
		(groups[key][1] as Array).append(id)
		if kind == 2:
			groups[key][2] = 2
			groups[key][3] = town_r
	var placed: Array = _tent_rects()
	var step := (ARMY_W + ARMY_GAP) * m * (0.8 if m < 0.8 else 1.0)
	var soft: Array = []   # the besiegers' own cells
	for key in order:
		if int(groups[key][2]) == 2:
			soft.append(_group_rect(groups[key][0], (groups[key][1] as Array).size(), false, m))
	for pass_kind in [0, 1, 2]:
		for key in order:
			var g: Array = groups[key]
			if int(g[2]) != pass_kind:
				continue
			var ids: Array = g[1]
			var n := ids.size()
			var c: Vector2 = g[0]
			if pass_kind == 2:
				c = _ring_nudge(c, n, int(g[3]), str(key), placed, m)
			placed.append(_group_rect(c, n, pass_kind == 1, m))
			for k in n:
				if pass_kind == 1:
					out[int(ids[k])] = c + Vector2(0, k * (ARMY_H * m * 0.9 + 3.0))
				else:
					out[int(ids[k])] = c + Vector2((k - (n - 1) * 0.5) * step, 0)
	return out


## The overlay is eight canvas items drawn in this order (children of this node, which itself draws nothing and
## never moves): the planned paths, the settlements and names, the selected fleet's reach (and its landing beaches and
## boarding cells), the sea (blockades, the lanes at war and raided, wrecks: static), the fleets (storms, the flota's
## course, voyages and the ships: redrawn 10 times a second, the ships bob), the selected army's halo, the armies, the
## paths' badges. Each keeps the view it was drawn for. When the view moves, a pure pan only slides a node
## (translation) and a small zoom step also scales it about the screen origin: positions stay exact, markers are a few
## percent off in size until that node is drawn again, one node per frame (the one furthest off first), so a pinch
## never redraws everything in one frame. A change of the state (queue_redraw on this node) redraws all at once.
## Each part is recorded into an OvBatch (ov_batch.gd) and emitted in a few draw calls (2026-10-29).
enum { P_PATHS, P_SITES, P_REACH, P_SEA, P_FLEETS, P_GLOW, P_ARMIES, P_TIPS }
const PART_NAMES := ["ov_paths", "ov_sites", "ov_reach", "ov_sea", "ov_fleets", "ov_glow", "ov_armies", "ov_tips"]
const BOB_DT := 0.1          # s between the fleets' redraws for the bobbing (10 Hz, as Quality Low's ships were)
## The miniatures' ships (minis_layer.gd) are to be redrawn in this frame: a bob step (BOB_DT; the fleets here move
## in the same frames), the state redrawn, or the voyages or the selected fleet changed.
signal ships_redraw
const ZOOM_SLIDE := 0.16     # a node further off than this is redrawn at once
const ZOOM_EAGER := 0.02     # ... one a frame once it is further off than this
var _nodes: Array = []
var traders: Node2D = null   # the lane traders' node (lane_traders.gd)
var _dx: Array = []          # Transform2D each node was drawn for
var _dz: Array = []          # the zoom each node was drawn for
var _ci = null               # what the part draws on: _b (or a CanvasItem)
var _b := OvBatch.new()      # the parts are recorded into this batch and emitted in a few draw calls (ov_batch.gd)
var _drawn_once := false
var _pos_cache := {}
var _pos_key: Array = []
var _army_pos := {}          # the positions the armies were drawn at (the halo's)
var _army_epoch := -1
var _epoch := 0              # bumped by a state redraw: the cached positions are void
var _last_xf := Transform2D.IDENTITY
var _devs := [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]   # each node's scale error as last slid
var _bob_due := false        # the fleets asked to be redrawn for the bobbing (at the next bob step)
var _bob_acc := 0.0          # s since the last bob step
var _sea_raid: Array = []    # the raid_lanes the sea part was drawn with
var _fpos_cache := {}        # fleet_positions() for _fpos_key
var _fpos_key: Array = []
var _raid_epoch := -1        # the state redraw _raider_ids is of
## Profiling only (tests/look_prof.gd --parts): parts of the overlay left out: "markers", "names", "standards",
## "lastseen", "fleets", "lanes" (the lanes at war and raided, blockades, wrecks, storms, the flota's course).
static var prof_off := {}


func _ready() -> void:
	for i in PART_NAMES.size():
		var nd := Node2D.new()
		nd.draw.connect(_draw_part.bind(i))
		add_child(nd)
		_nodes.append(nd)
		_dx.append(Transform2D.IDENTITY)
		_dz.append(1.0)
	# the lane traders (lane_traders.gd): between the sea part and the fleets; delete these four lines with the file
	traders = LaneTraders.new()
	traders.overlay = self
	add_child(traders)
	move_child(traders, (_nodes[P_FLEETS] as Node2D).get_index())


## (the state changed: every part is drawn again, in this frame)
func _draw() -> void:
	if _nodes.is_empty():
		return
	_epoch += 1
	_drawn_once = true
	for nd in _nodes:
		(nd as Node2D).queue_redraw()
	ships_redraw.emit()


## The view moved to xf (called by the screen every frame it moves): nodes are slid, and one is queued for a redraw
## (none while the map redraws its own staged parts: heavy).
func set_view(xf: Transform2D, heavy := false) -> void:
	xform = xf
	if not _drawn_once:
		queue_redraw()
		return
	var worst := -1
	var worst_dev := ZOOM_EAGER
	for i in _nodes.size():
		var j := i   # (the halo rides with the armies, the badges with the paths)
		if i == P_GLOW:
			j = P_ARMIES
		elif i == P_TIPS:
			j = P_PATHS
		var dev := _slide(_nodes[i], _dx[j], xf)
		_devs[i] = dev
		if dev < 0.0 or dev > ZOOM_SLIDE:
			(_nodes[i] as Node2D).queue_redraw()   # cannot slide it (rotated / too far off): draw it now
		elif dev > worst_dev and i != P_GLOW and i != P_TIPS and i != P_FLEETS:
			worst = i
			worst_dev = dev
	if worst >= 0 and not heavy:
		(_nodes[worst] as Node2D).queue_redraw()


## Slide node nd (drawn for view d) to view xf; its scale error (0 for a pan), or -1 when a slide cannot show it.
func _slide(nd: Node2D, d: Transform2D, xf: Transform2D) -> float:
	if d.x.y != 0.0 or d.y.x != 0.0 or xf.x.y != 0.0 or xf.y.x != 0.0 or d.x.x <= 0.0 or d.y.y <= 0.0:
		return -1.0
	var sx := xf.x.x / d.x.x
	var sy := xf.y.y / d.y.y
	nd.scale = Vector2(sx, sy)
	nd.position = xf.origin - Vector2(sx * d.origin.x, sy * d.origin.y)
	return maxf(absf(sx - 1.0), absf(sy - 1.0))


func _process(delta: float) -> void:
	# the bobbing steps (10 Hz, by the frames' time: the same frames on every run at a fixed frame rate)
	_bob_acc += delta
	if _bob_acc >= BOB_DT:
		_bob_acc = fmod(_bob_acc, BOB_DT)
		if _bob_due and _drawn_once:
			(_nodes[P_FLEETS] as Node2D).queue_redraw()
		ships_redraw.emit()
	# once the view has stopped, any node still off is drawn again, one a frame (not in a frame of the map's staged redraw)
	if _drawn_once and xform == _last_xf:
		var mv: Node = MapView.instance
		if mv == null or not is_instance_valid(mv) or not mv.heavy_pending():
			for i in [P_ARMIES, P_SITES, P_SEA, P_PATHS, P_REACH, P_FLEETS]:
				if float(_devs[i]) > 0.0005:
					(_nodes[i] as Node2D).queue_redraw()
					break
	_last_xf = xform


func _begin_part(i: int) -> void:
	_b.begin()
	_b.ink = InkLines.new() if i == P_SEA and InkLines.state == 1 else null   # (the lanes' dashes: ink_lines.gd)
	_ci = _b
	if i == P_GLOW or i == P_TIPS:
		return   # (they ride with the armies / the paths: same transform, set when those are drawn)
	_dx[i] = xform
	_dz[i] = zoom
	_devs[i] = 0.0
	(_nodes[i] as Node2D).position = Vector2.ZERO
	(_nodes[i] as Node2D).scale = Vector2.ONE
	if i == P_FLEETS:
		_bob_due = false
	if i == P_PATHS:   # the badges node takes the paths' transform
		(_nodes[P_TIPS] as Node2D).position = Vector2.ZERO
		(_nodes[P_TIPS] as Node2D).scale = Vector2.ONE
		(_nodes[P_TIPS] as Node2D).queue_redraw()
	if i == P_ARMIES:   # the halo node takes the armies' transform
		(_nodes[P_GLOW] as Node2D).position = Vector2.ZERO
		(_nodes[P_GLOW] as Node2D).scale = Vector2.ONE
		(_nodes[P_GLOW] as Node2D).queue_redraw()


func _draw_part(i: int) -> void:
	if state.is_empty():
		return
	var t0 := ZProf.begin()
	_begin_part(i)
	match i:
		P_PATHS:
			_paths_body()
		P_SITES:
			_sites_body()
		P_REACH:
			_reach_body()
		P_SEA:
			_sea_body()
		P_FLEETS:
			_fleets_body()
		P_GLOW:
			_glow_body()
		P_ARMIES:
			_armies_body()
		P_TIPS:
			_tips_body()
	_b.flush(_nodes[i])
	_ci = null
	ZProf.add(PART_NAMES[i], t0)


## A selection changed but not the state: only the parts that show it are drawn again (paths with the zones,
## links and badges; fleets with the sea reach; armies with the merge glyphs and the halo), not the settlements.
## Before the first draw: everything.
func redraw_parts(p_paths: bool, p_fleets: bool, p_armies: bool) -> void:
	if not _drawn_once:
		queue_redraw()
		return
	if p_paths:
		(_nodes[P_PATHS] as Node2D).queue_redraw()
	if p_fleets:
		ships_redraw.emit()
		(_nodes[P_REACH] as Node2D).queue_redraw()
		(_nodes[P_FLEETS] as Node2D).queue_redraw()
		if raid_lanes != _sea_raid:
			(_nodes[P_SEA] as Node2D).queue_redraw()   # (the lanes the selected fleet can raid are drawn with the sea)
	if p_armies:
		(_nodes[P_ARMIES] as Node2D).queue_redraw()
	(_nodes[P_GLOW] as Node2D).queue_redraw()


## Redraw only the fleets (the ships bob: at the next bob step, see _process) or only the armies' halo (a selected
## army): nothing before the first draw.
func redraw_fleets() -> void:
	if _drawn_once:
		_bob_due = true


func redraw_armies() -> void:
	if _drawn_once:
		(_nodes[P_GLOW] as Node2D).queue_redraw()
		if merge_tap >= 0:   # (the merge target's ring pulses too)
			(_nodes[P_ARMIES] as Node2D).queue_redraw()


## The armies' marker positions for the draw of this frame (kept while neither the state, the view nor the zoom changed).
func _positions() -> Dictionary:
	var key := [_epoch, xform, zoom]
	if _pos_key != key:
		var tz := ZProf.begin()
		_pos_cache = army_positions()
		_pos_key = key
		ZProf.add("ov_armypos", tz)
	return _pos_cache


func _mk_of(z: float) -> float:
	return clampf(z / 0.7, 0.5, 1.0)


func set_drop(id: int) -> void:
	if id != drop_army:
		drop_army = id
		if _drawn_once:
			(_nodes[P_GLOW] as Node2D).queue_redraw()


func _glow_body() -> void:
	if drop_army >= 0 and _army_epoch == _epoch and _army_pos.has(drop_army):
		var dm := _mk_of(_dz[P_ARMIES])
		var dc: Vector2 = _army_pos[drop_army] + Vector2(-2.0, -2.0) * maxf(dm, 0.8)
		var dr := 24.0 * maxf(dm, 0.8) + 1.5 * sin(pulse * 6.0)
		_ci.draw_circle(dc, dr, Color(Color(1.0, 0.85, 0.3), 0.22))
		_ci.draw_arc(dc, dr, 0, TAU, 36, Color(Color(1.0, 0.85, 0.3), 0.95), 2.4, true)
	var sel := selected_army
	if sel < 0 or _army_epoch != _epoch or not _army_pos.has(sel):
		return
	var c: Vector2 = _army_pos[sel]
	var m := _mk_of(_dz[P_ARMIES])
	var hc := c + Vector2(-2.0, -2.0) * maxf(m, 0.8)
	var hr := 21.0 * maxf(m, 0.8) + 1.5 * sin(pulse * 5.0)
	_ci.draw_circle(hc, hr, Color(COL_SELECTED, 0.26))
	_ci.draw_arc(hc, hr, 0, TAU, 32, Color(COL_SELECTED, 0.7), 1.6, true)


func _tips_body() -> void:
	var m := mk()
	for tp in _tips:
		if not (str(tp[1]) == "merge" and str(tp[3]).begins_with("Too many")):
			draw_intent(_ci, tp[0], str(tp[1]), tp[2], m)  # an over-full merge: the grey path and caption only
		if (tp as Array).size() > 3 and str(tp[3]) != "":
			_caption(tp[0], str(tp[3]), tp[2])


func _paths_body() -> void:
	var pos := _positions()
	for m in moves:
		var id := int(m[0])
		if not pos.has(id):
			continue
		var from: Vector2 = pos[id]
		var to := to_screen(Geo.site(int(m[1]))) + Vector2(0, 8)
		var col := COL_MOVE
		if siege_moves.has(id):
			col = COL_SIEGE
		elif attack_moves.has(id):
			col = COL_ATTACK
		draw_arrow(_ci, from, to, col)
	for pth in paths:
		_path(pth, pos)
	_tips = []
	if grid:
		_draw_trails()
		for z in zones:
			draw_zone(_ci, to_screen(z[0]), float(z[1]) * zoom)
		_draw_links(pos)
		for pth in paths6:
			_path6(pth, pos)
		if not drag.is_empty():
			_path6(drag, pos)


func _sites_body() -> void:
	# Settlements and names.
	var show_names := zoom >= 0.5
	var m := mk()
	var placed: Array = []   # label rects already drawn this frame (neighbouring towns do not print over each other)
	for r in CData.region_count():
		var p := to_screen(site_point(r))
		var rs: Dictionary = state["regions"][r]
		var lvl := int(rs["level"])
		var rad: float = _site_rad(r)
		var w := FogView.shown_walls(state, r)   # (fog: the walls as last seen)
		# every settlement has a marker that is its tap target: the relief style's, and over a table-style model that
		# is small or sparse (a bare name over a hut was hard to hit); the harbour mark for a port
		var big := CData.is_capital(r) or CData.KEY_CITIES.has(str(CData.REGIONS[r]["key"]))   # (capitals and key cities keep their look when far)
		var far_sym := MapView.far_lod and (not Minis.on_sites or zoom < Minis.SITE_MIN_ZOOM)   # zoomed out: an ink symbol by level
		var oc := CData.faction_color(FogView.shown_owner(state, r)) if FogView.shown_owner(state, r) >= 0 else Color(0.62, 0.62, 0.58)
		if prof_off.has("markers"):
			pass
		elif far_sym:
			var star := CData.is_capital(r) or big
			var kc := CData.KEY_CITIES.has(str(CData.REGIONS[r]["key"]))
			var owned := FogView.shown_owner(state, r) >= 0
			var fport := (CFleet.harbour(r) >= 0 or CFleet.dock(r) >= 0) and not FogView.never(r)
			_glyph(_ci, ["far", lvl, star, kc, owned, oc, fport], p, func(gb, q: Vector2): draw_far_site(gb, q, lvl, star, kc, owned, oc, fport))
		elif not Minis.on_sites or Minis.weak(zoom, r):
			var sr0 := rad * (1.0 if not Minis.on_sites else 0.85)
			var sport := (CFleet.harbour(r) >= 0 or CFleet.dock(r) >= 0) and not FogView.never(r)
			_glyph(_ci, ["site", sr0, oc, w, m, sport], p, func(gb, q: Vector2): draw_site(gb, q, sr0, oc, w, m, sport))
		var sg := CState.siege_at(state, r) if FogView.region_seen(r) else {}   # (fog: a siege out of sight is not shown)
		if not sg.is_empty() and not prof_off.has("markers"):
			var sr := siege_ring_radius(r)   # (round the ring the besiegers stand on)
			draw_siege_ring(_ci, p, sr, CData.faction_color(int(sg["f"])), m)
		if CData.KEY_CITIES.has(str(CData.REGIONS[r]["key"])) and not far_sym and not prof_off.has("markers"):
			_glyph(_ci, ["key", rad], p, func(gb, q: Vector2): draw_key_city(gb, q, rad))
		if (show_names or lvl == CData.CITY) and (not MapView.far_lod or big) and not FogView.never(r) and not prof_off.has("names"):
			var nm := str(CData.REGIONS[r]["city"])
			var fs := int(round(FONT * (0.85 + 0.15 * m)))
			# At the diorama zoom the names are 18 px or more and use the display face; smaller zooms are as before.
			var disp := zoom >= DIORAMA_ZOOM and MenuStyle.display_font(true) != null
			if disp:
				fs = int(round(minf(22.0, 18.0 + (zoom - DIORAMA_ZOOM) * 4.0)))
			var tw := text_w(nm, fs, disp)
			var tp := p + Vector2(-tw * 0.5, -rad - 5.0 - Minis.label_lift_of(zoom, r))
			for _k in 4:
				var lr := Rect2(tp.x - 2.0, tp.y - fs, tw + 4.0, fs + 3.0)
				var hit := false
				for o in placed:
					if lr.intersects(o):
						hit = true
						break
				if not hit:
					placed.append(lr)
					break
				tp.y -= fs + 3.0
			put(_ci, tp, nm, fs, Color(1, 1, 0.95), 4, Color(0, 0, 0, 0.75), disp)
	# Pending battles.
	for b in state["battles"]:
		if not FogView.battle_seen(state, b):
			continue
		var p := to_screen(Geo.site(int(b["r"]))) + Vector2(16, -14)
		if grid and b.has("x"):
			p = to_screen(cell_point(CGrid.at(int(b["x"]), int(b["y"])))) + Vector2(0, -16)
		_glyph(_ci, ["bat"], p, func(gb, q: Vector2): draw_battle(gb, q, 1.0))
	for mkr in markers:
		draw_battle(_ci, to_screen(mkr[0]) + Vector2(0, -16), clampf(float(mkr[1]), 0.0, 1.0))


## The selected fleet's reach this turn, the beaches a landing can aim for, the boarding cells.
func _reach_body() -> void:
	for lp in _sea_reach_fill:
		_ci.draw_colored_polygon(xform * (lp as PackedVector2Array), Color(1.0, 0.98, 0.85, 0.16))
	for lp in sea_reach:
		var cl: PackedVector2Array = xform * (lp as PackedVector2Array)
		cl.append(cl[0])
		_ci.draw_polyline(cl, Color(0, 0, 0, 0.35), 3.0, true)
		_ci.draw_polyline(cl, Color(1, 0.98, 0.85, 0.6), 1.5, true)
	# The beaches a landing can aim for: sand-gold, glowing, over the coast.
	if _landing_segs.size() >= 2:
		var sp: PackedVector2Array = xform * _landing_segs
		_ci.draw_multiline(sp, Color(0, 0, 0, 0.4), 6.0, true)
		_ci.draw_multiline(sp, Color(COL_LANDING.r, COL_LANDING.g, COL_LANDING.b, 0.5), 4.6, true)
		_ci.draw_multiline(sp, Color(1.0, 0.98, 0.8, 0.95), 2.2, true)
	for bcs in [board_cells, pickup_cells]:
		for c in bcs:
			_draw_board_cell(int(c))


## The sea, static between state redraws: blockaded ports, the lanes (raidable by the selected fleet, at war,
## raided), wrecks.
func _sea_body() -> void:
	_sea_raid = raid_lanes.duplicate()
	if not state.has("fleets"):
		return
	var m := mk()
	for r in (CData.region_count() if not prof_off.has("lanes") else 0):
		var bk := CSea.blockader(state, r)
		if bk >= 0 and CFleet.harbour(r) >= 0 and FogView.region_seen(r):
			draw_blockade(_ci, to_screen(cell_point(CFleet.harbour(r))),
				(CSea.k("BLOCKADE_CELLS", 3) + 0.5) * CGrid.cell_px() * zoom, CData.faction_color(bk), m)
			var hp := to_screen(cell_point(CFleet.harbour(r)))   # (lanes) the blockaded harbour mark: a red ring
			_ci.draw_arc(hp, 9.0 * m, 0.0, TAU, 24, Color(0, 0, 0, 0.7), 4.6 * m, true)
			_ci.draw_arc(hp, 9.0 * m, 0.0, TAU, 24, COL_RAID, 2.6 * m, true)
	if not prof_off.has("lanes"):
		_draw_lanes(m)
		_draw_wrecks(m)


## Fleets: storms, the flota's course, the planned voyages, then the ships.
func _fleets_body() -> void:
	if state.has("fleets"):
		var fpos := _fleet_positions()
		if not prof_off.has("lanes"):
			_draw_storms(mk())
			_flota_course(fpos)
		for fp in fleet_paths:
			_fleet_path(fp, fpos)
		if _raid_epoch != _epoch:
			_raid_epoch = _epoch
			_raider_ids = raider_fleet_ids()
		for fl in (state["fleets"] if not prof_off.has("fleets") else []):
			if fpos.has(int(fl["id"])):
				_fleet_marker(fpos[int(fl["id"])], fl)


## fleet_positions() for this frame's draw (kept while neither the state, the view nor the zoom changed).
func _fleet_positions() -> Dictionary:
	var key := [_epoch, xform, zoom, Minis.on_sites]
	if _fpos_key != key:
		_fpos_cache = fleet_positions()
		_fpos_key = key
	return _fpos_cache


func _armies_body() -> void:
	var m := mk()
	var pos := _positions()
	_army_pos = pos
	_army_epoch = _epoch
	if not prof_off.has("lastseen"):
		_last_seen_markers(m)
	# Armies.
	for a in (state["armies"] if not prof_off.has("standards") else []):
		var id := int(a["id"])
		if not pos.has(id):
			continue
		_army_marker(pos[id], a)
	for mm in merge_marks:
		if int(mm[1]) in [0, 1] and pos.has(int(mm[0])):
			var gp: Vector2 = pos[int(mm[0])] + Vector2(-ARMY_W * 0.5, ARMY_H * 0.5) * m
			if int(mm[0]) == merge_tap:
				_ci.draw_arc(gp, 7.0 * m + 4.0 + 1.5 * sin(pulse * 6.0), 0, TAU, 20, Color(1, 1, 1, 0.9), 2.0, true)
			draw_merge_glyph(_ci, gp, int(mm[1]), m)


## Fog of war: where the planner's team last saw armies and fleets that are out of sight now (CSight.markers):
## [marker, screen point] in marker order, two on one cell side by side.
func marker_spots() -> Array:
	var out: Array = []
	if not FogView.on or not grid:
		return out
	var m := mk()
	var by_cell := {}
	for mkr in FogView.marks:
		var c := int(mkr["cell"])
		var k: int = by_cell.get(c, 0)
		by_cell[c] = k + 1
		out.append([mkr, to_screen(cell_point(c)) + Vector2(k * (ARMY_W + ARMY_GAP) * m, 0)])
	return out


## The last-seen marker under screen point p ({} none).
func marker_at(p: Vector2) -> Dictionary:
	var m := mk()
	var best := {}
	var best_d := 1e9
	for e in marker_spots():
		var q: Vector2 = e[1]
		if absf(p.x - q.x) <= ARMY_W * 0.5 * m + 6.0 and absf(p.y - q.y) <= ARMY_H * 0.5 * m + 8.0 and p.distance_to(q) < best_d:
			best = e[0]
			best_d = p.distance_to(q)
	return best


const MARKER_A := 0.5


## A faded shield (army) or sail (fleet) in the faction's colour with the count as last seen, a dashed outline.
func _last_seen_markers(m: float) -> void:
	for e in marker_spots():
		var mkr: Dictionary = e[0]
		var col := CData.faction_color(int(mkr["f"]))
		var lsf := int(mkr["kind"]) == 1
		var lsn := str(int(mkr["units"]))
		_glyph(_ci, ["seen", m, lsf, col, lsn], e[1], func(gb, q: Vector2): draw_last_seen(gb, q, m, lsf, col, lsn))
		var c: Vector2 = e[1]
		var tt := "seen t%d" % int(mkr["turn"])
		var tfs := int(round(11 * maxf(m, 0.8)))
		put(_ci, c + Vector2(-text_w(tt, tfs) * 0.5, ARMY_H * 0.5 * m + 6.0 + tfs), tt, tfs, Color(0.85, 0.88, 0.95, 0.8), 3, Color(0, 0, 0, 0.7))


## The last-seen marker itself (shield for an army, hull for a fleet) at c, scale m, with its count n.
static func draw_last_seen(ci, c: Vector2, m: float, fleet: bool, col: Color, n: String) -> void:
	var fcol := Color(col.r, col.g, col.b, MARKER_A)
	var pts: PackedVector2Array
	if fleet:
		var s := FLEET_W * 0.5 * m
		pts = PackedVector2Array([c + Vector2(-s, 0.15 * s), c + Vector2(s, 0.15 * s), c + Vector2(0.62 * s, 0.62 * s), c + Vector2(-0.7 * s, 0.62 * s)])
	else:
		var rect := Rect2(c - Vector2(ARMY_W, ARMY_H) * 0.5 * m, Vector2(ARMY_W, ARMY_H) * m)
		pts = PackedVector2Array([rect.position, rect.position + Vector2(rect.size.x, 0),
			rect.position + Vector2(rect.size.x, rect.size.y - 6 * m), c + Vector2(0, rect.size.y * 0.5 + 3 * m),
			rect.position + Vector2(0, rect.size.y - 6 * m)])
	ci.draw_colored_polygon(pts, fcol)
	for k in pts.size():
		ci.draw_dashed_line(pts[k], pts[(k + 1) % pts.size()], Color(0.9, 0.9, 0.85, 0.6), 1.4, 4.0, true)
	var afs := int(round(14 * maxf(m, 0.75)))
	put(ci, c + Vector2(-text_w(n, afs) * 0.5, afs * 0.3), n, afs, Color(1, 1, 1, 0.75), 3, Color(0, 0, 0, 0.6))


# ------------------------------------------------------------- painters ---
# Static, on any CanvasItem (the map key) or an OvBatch (the map: ov_batch.gd records the same calls as triangles).

## A battle: a red disc with crossed swords (alpha fades a popped marker).
static func draw_battle(ci, p: Vector2, alpha: float) -> void:
	ci.draw_circle(p, 11.0, Color(COL_BATTLE, 0.95 * alpha))
	ci.draw_arc(p, 11.0, 0, TAU, 20, Color(1, 1, 1, alpha), 1.5, true)
	ci.draw_line(p + Vector2(-5, -5), p + Vector2(5, 5), Color(1, 1, 1, alpha), 2.2, true)
	ci.draw_line(p + Vector2(5, -5), p + Vector2(-5, 5), Color(1, 1, 1, alpha), 2.2, true)


## Version 6 replay: a faint line in the army's colour behind it.
static func draw_trail(ci, pts: PackedVector2Array, faction_col: Color) -> void:
	var col := faction_col.lightened(0.3)
	col.a = 0.8
	ci.draw_polyline(pts, Color(0, 0, 0, 0.5), 6.0, true)
	ci.draw_polyline(pts, col, 3.5, true)


## Version 6: an enemy army's zone of control (red circle).
static func draw_zone(ci, c: Vector2, rad: float) -> void:
	ci.draw_circle(c, rad, ZONE_FILL)
	ci.draw_arc(c, rad, 0, TAU, 40, Color(0.0, 0.0, 0.0, 0.45), 3.0, true)
	ci.draw_arc(c, rad, 0, TAU, 40, ZONE_EDGE, 1.6, true)


## Version 6: a support (kind 0, yellow) or attack (kind 1, red) line.
static func draw_link(ci, a: Vector2, b: Vector2, kind: int) -> void:
	ci.draw_line(a, b, Color(0, 0, 0, 0.5), 5.0, true)
	ci.draw_dashed_line(a, b, COL_SUPPORT if kind == 0 else COL_THREAT, LINK_W, LINK_DASH, true)


## The colour of a planned path by its kind (a merge caption "Too many
## units ..." greys it).
static func path_color(kind: String, caption: String = "") -> Color:
	if ATTACK_KINDS.has(kind):
		return COL_ATTACK
	if SIEGE_KINDS.has(kind):
		return COL_SIEGE
	if kind == "merge":
		return COL_MERGE_NO if caption.begins_with("Too many") else COL_MERGE
	return COL_MOVE


## Version 6: one step of a planned path: solid this turn, dashed after.
static func draw_path_step(ci, a: Vector2, b: Vector2, col: Color, this_turn: bool, m: float) -> void:
	if this_turn:
		ci.draw_line(a, b, Color(0, 0, 0, 0.6), (PATH_W_NOW + 3.0) * m, true)
		ci.draw_line(a, b, col, PATH_W_NOW * m, true)
	else:
		ci.draw_dashed_line(a, b, Color(0, 0, 0, 0.5), (PATH_W_LATER + 3.0) * m, PATH_DASH, true)
		ci.draw_dashed_line(a, b, col.darkened(0.05), PATH_W_LATER * m, PATH_DASH, true)


## Version 6: the ring where this turn's march ends.
static func draw_turn_end(ci, e: Vector2, col: Color, m: float) -> void:
	ci.draw_circle(e, 7.0 * m, Color(0, 0, 0, 0.55))
	ci.draw_arc(e, 7.0 * m, 0, TAU, 20, col, 3.0 * m, true)


## The intent at a path's end: a small badge (swords an attack, a tent a
## siege, a plus a merge, a tower going inside); none for a plain march (its
## line ends there; the ring marks where this turn's part ends).
## The faction whose land region r is when an army of f there would be a trespass (CDip.may_cross without passage,
## the rule end_turn charges for), else -1.
static func trespass_owner(st: Dictionary, f: int, r: int) -> int:
	if st.is_empty() or r < 0 or not CDip.on(st) or not CState.is_human(st, f):
		return -1
	var o := CState.owner(st, r)
	if o < 0 or o == f or not CDip.may_cross(st, f, o) or CDip.has_passage(st, f, o):
		return -1
	return o


static func has_intent(kind: String) -> bool:
	return ATTACK_KINDS.has(kind) or SIEGE_KINDS.has(kind) or kind == "merge" or kind == "inside" or kind == "trespass"


static func draw_intent(ci, p: Vector2, kind: String, col: Color, m: float) -> void:
	if not has_intent(kind):
		return
	if kind == "trespass":
		# A warning triangle with an exclamation mark.
		var tsz := 10.0 * m
		var tri := PackedVector2Array([p + Vector2(0, -tsz), p + Vector2(tsz * 1.05, tsz * 0.8), p + Vector2(-tsz * 1.05, tsz * 0.8)])
		var ol := PackedVector2Array(tri)
		ol.append(tri[0])
		ci.draw_polyline(ol, Color(0, 0, 0, 0.85), 3.5, true)
		ci.draw_colored_polygon(tri, col)
		ci.draw_line(p + Vector2(0, -tsz * 0.35), p + Vector2(0, tsz * 0.15), COL_OUTLINE, 2.2 * m, true)
		ci.draw_circle(p + Vector2(0, tsz * 0.5), 1.4 * m, COL_OUTLINE)
		return
	var r := 9.0 * m
	ci.draw_circle(p, r + 1.5, Color(0, 0, 0, 0.75))
	ci.draw_circle(p, r, col.darkened(0.35))
	var w := Color(1, 1, 1, 0.95)
	if ATTACK_KINDS.has(kind):
		ci.draw_line(p + Vector2(-5, -5) * m, p + Vector2(5, 5) * m, w, 2.2, true)
		ci.draw_line(p + Vector2(5, -5) * m, p + Vector2(-5, 5) * m, w, 2.2, true)
	elif SIEGE_KINDS.has(kind):
		var ts := 5.5 * m
		ci.draw_colored_polygon(PackedVector2Array([p + Vector2(0, -ts), p + Vector2(ts, ts * 0.8), p + Vector2(-ts, ts * 0.8)]), w)
	elif kind == "merge":
		ci.draw_line(p + Vector2(-5, 0) * m, p + Vector2(5, 0) * m, w, 2.4, true)
		ci.draw_line(p + Vector2(0, -5) * m, p + Vector2(0, 5) * m, w, 2.4, true)
	else:  # inside
		ci.draw_rect(Rect2(p - Vector2(4, 3) * m, Vector2(8, 8) * m), w)
		for k in 3:
			ci.draw_rect(Rect2(p + Vector2(-4 + 3.0 * k, -6) * m, Vector2(2, 3) * m), w)


## A merge candidate's glyph at p: kind 0 an army of ours it can merge
## into (in reach, room for the units: green plus), 1 an allied player's
## army next to it to give units to (gold gift box).
static func draw_merge_glyph(ci, p: Vector2, kind: int, m: float) -> void:
	var r := 7.0 * m
	ci.draw_circle(p, r + 1.2, Color(0, 0, 0, 0.85))
	ci.draw_circle(p, r, MERGE_COLS[clampi(kind, 0, 1)])
	var w := Color(1, 1, 1)
	if kind == 1:
		ci.draw_rect(Rect2(p - Vector2(4, 3) * m, Vector2(8, 7) * m), w, false, 1.5)
		ci.draw_line(p + Vector2(0, -4) * m, p + Vector2(0, 4) * m, w, 1.5)
		ci.draw_line(p + Vector2(-4, 0) * m, p + Vector2(4, 0) * m, w, 1.5)
	else:
		ci.draw_line(p + Vector2(-4, 0) * m, p + Vector2(4, 0) * m, w, 2.0, true)
		ci.draw_line(p + Vector2(0, -4) * m, p + Vector2(0, 4) * m, w, 2.0, true)


## A settlement: walls (w 0-3), a white rim and the owner's colour (the
## same faction colour as its banners and the land's owner band).
static func draw_site(ci, p: Vector2, rad: float, owner_col: Color, w: int, m: float, port := false) -> void:
	if w > 0:
		draw_wall_ring(ci, p, rad, w, m)
	ci.draw_circle(p, rad + 2.5, COL_OUTLINE)
	ci.draw_circle(p, rad + 1.5, Color(1, 1, 1, 0.95))
	ci.draw_circle(p, rad, owner_col)
	if port:
		draw_harbour_mark(ci, p + Vector2(rad + (6.5 + 1.2 * w) * m, rad * 0.5 + 1.0), m)


const INK := Color(0.13, 0.08, 0.04)
const PARCH := Color(0.93, 0.87, 0.7)


## A settlement below the miniatures' zoom (visual pass part 2): an ink symbol by level over a tiny parchment disc,
## the owner's colour a thin ring round it. Level 0 a small circle, 1 a circle with a tick (a tiny tower), 2 a ring
## with battlement notches; a capital a star, a key city the white star; a port gets a small ink anchor.
static func draw_far_site(ci, p: Vector2, lvl: int, star: bool, key: bool, owned: bool, owner_col: Color, port: bool) -> void:
	var r: float = [3.0, 4.0, 5.0][clampi(lvl, 0, 2)] + (2.0 if star else 0.0)
	var dr := r + 2.2
	ci.draw_circle(p, dr + 0.8, Color(0.08, 0.05, 0.03, 0.5))
	ci.draw_circle(p, dr, Color(PARCH.r, PARCH.g, PARCH.b, 0.92))
	ci.draw_arc(p, dr - 0.4, 0, TAU, 24, owner_col if owned else Color(0.62, 0.6, 0.55), 1.6, true)
	if star:
		var pts := PackedVector2Array()
		for k in 10:
			var a := -PI * 0.5 + PI * k / 5.0
			pts.append(p + Vector2(cos(a), sin(a)) * (r if k % 2 == 0 else r * 0.45))
		ci.draw_colored_polygon(pts, Color.WHITE if key else INK)
		var o := pts.duplicate()
		o.append(pts[0])
		ci.draw_polyline(o, INK, 1.2, true)
	elif lvl <= 0:
		ci.draw_arc(p, r * 0.6, 0, TAU, 14, INK, 1.5, true)
	elif lvl == 1:
		ci.draw_arc(p, r * 0.75, 0, TAU, 16, INK, 1.5, true)
		ci.draw_line(p + Vector2(0, -r * 0.75), p + Vector2(0, -r * 1.35), INK, 1.8, true)
	else:
		ci.draw_arc(p, r * 0.75, 0, TAU, 18, INK, 1.8, true)
		for k in 6:
			var a2 := TAU * k / 6.0 - PI * 0.5
			var d := Vector2(cos(a2), sin(a2))
			ci.draw_line(p + d * r * 0.75, p + d * r * 1.25, INK, 1.6, true)
	if port:
		var q := p + Vector2(dr + 3.5, dr * 0.5)
		ci.draw_line(q + Vector2(0, -3.0), q + Vector2(0, 3.0), INK, 1.4, true)
		ci.draw_line(q + Vector2(-2.0, -1.5), q + Vector2(2.0, -1.5), INK, 1.2, true)
		ci.draw_arc(q + Vector2(0, 0.5), 2.6, 0.15 * PI, 0.85 * PI, 8, INK, 1.3, true)


## A harbour mark: a small white anchor on a dark disc (a settlement with a port).
static func draw_harbour_mark(ci, p: Vector2, m: float) -> void:
	var s := maxf(m, 0.7) * 4.1   # (75 % of its first size, and a quieter disc: owner 2026-10-23)
	ci.draw_circle(p, s * 1.35, Color(0.06, 0.1, 0.16, 0.6))
	var wc := Color(0.95, 0.96, 0.98)
	ci.draw_arc(p + Vector2(0, -s * 0.72), s * 0.2, 0, TAU, 10, wc, 1.2, true)
	ci.draw_line(p + Vector2(0, -s * 0.5), p + Vector2(0, s * 0.8), wc, 1.4, true)
	ci.draw_line(p + Vector2(-s * 0.45, -s * 0.2), p + Vector2(s * 0.45, -s * 0.2), wc, 1.3, true)
	ci.draw_arc(p + Vector2(0, s * 0.1), s * 0.7, 0.15 * PI, 0.85 * PI, 10, wc, 1.4, true)


## A key city (the default victory condition): a white star with a dark
## edge on the settlement (no gold: gold is the gift glyph).
static func draw_key_city(ci, p: Vector2, rad: float) -> void:
	var ro := maxf(rad * 0.78, 3.5)
	var ri := ro * 0.45
	var pts := PackedVector2Array()
	for k in 10:
		var a := -PI * 0.5 + PI * k / 5.0
		pts.append(p + Vector2(cos(a), sin(a)) * (ro if k % 2 == 0 else ri))
	ci.draw_colored_polygon(pts, COL_KEY_CITY)
	var o := pts.duplicate()
	o.append(pts[0])
	ci.draw_polyline(o, COL_OUTLINE, 1.2, true)


## Walls: a stone ring round the settlement with towers on it, thicker and
## with more towers per wall level (1-3).
static func draw_wall_ring(ci, p: Vector2, rad: float, w: int, m: float) -> void:
	var rr := rad + (3.0 + 1.2 * w) * m
	var th := (1.6 + 0.9 * w) * m
	ci.draw_arc(p, rr, 0, TAU, 32, Color(0.12, 0.11, 0.09, 0.95), th + 1.6, true)
	ci.draw_arc(p, rr, 0, TAU, 32, Color(0.78, 0.74, 0.64), th, true)
	var n := 4 + 2 * w
	var ts := (2.0 + 0.7 * w) * m
	for k in n:
		var a := TAU * k / n - PI * 0.5
		var c := p + Vector2(cos(a), sin(a)) * rr
		ci.draw_rect(Rect2(c - Vector2(ts, ts) - Vector2(0.8, 0.8), Vector2(ts, ts) * 2.0 + Vector2(1.6, 1.6)), Color(0.12, 0.11, 0.09, 0.95))
		ci.draw_rect(Rect2(c - Vector2(ts, ts), Vector2(ts, ts) * 2.0), Color(0.84, 0.80, 0.70))


## Siege: a dashed ring in the besieger's colour with tents on its upper
## half (the army banners stand below the settlement).
static func draw_siege_ring(ci, p: Vector2, rad: float, col: Color, m: float) -> void:
	var rr := rad + 6.0 * m
	var n := 12
	for k in n:
		var a0 := TAU * k / n
		ci.draw_arc(p, rr, a0, a0 + TAU / n * 0.6, 6, Color(0, 0, 0, 0.75), 5.0 * m, true)
		ci.draw_arc(p, rr, a0, a0 + TAU / n * 0.6, 6, col.lightened(0.25), 3.0 * m, true)
	var ts := 5.5 * m
	for k in 5:
		var a := PI + PI * (k + 0.5) / 5  # left, over the top, to the right
		var c := p + Vector2(cos(a), sin(a)) * rr
		var tri := PackedVector2Array([c + Vector2(0, -ts), c + Vector2(ts, ts * 0.8), c + Vector2(-ts, ts * 0.8)])
		ci.draw_colored_polygon(tri, col)
		var o := tri.duplicate()
		o.append(tri[0])
		ci.draw_polyline(o, Color(1, 1, 1, 0.9), 1.2, true)


## A blockaded port: a dashed ring of radius rad round its harbour at p in
## the blockader's colour, a bar across the harbour mouth.
static func draw_blockade(ci, p: Vector2, rad: float, col: Color, m: float) -> void:
	var n := 16
	for k in n:
		var a0 := TAU * k / n
		ci.draw_arc(p, rad, a0, a0 + TAU / n * 0.55, 5, Color(0, 0, 0, 0.6), 4.0 * m, true)
		ci.draw_arc(p, rad, a0, a0 + TAU / n * 0.55, 5, col.lightened(0.3), 2.2 * m, true)
	var d := Vector2(7.0, -7.0) * m
	ci.draw_line(p - d, p + d, Color(0, 0, 0, 0.8), 5.0 * m, true)
	ci.draw_line(p - d, p + d, Color(1.0, 0.35, 0.25), 2.6 * m, true)
	ci.draw_circle(p, 3.0 * m, col.lightened(0.3))


## (Sea lanes) The lanes the selected fleet can raid, thicker; the lanes between ports at war (no trade) redrawn in a
## dull dark red-brown over the pale dashes (the same dash cut as MapView._draw_lanes); the lanes with a raider on them,
## dashed red with a "raided by <adjective>" badge at the midpoint (shown to the owners of its ports and to whoever
## sees the raider).
func _draw_lanes(m: float) -> void:
	for id in raid_lanes:
		var poly := MapView.lane_poly(int(id))
		if poly.size() >= 2:
			var pl: PackedVector2Array = xform * poly
			_ci.draw_polyline(pl, Color(0, 0, 0, 0.35), 6.0 * m, true)
			_ci.draw_polyline(pl, Color(1.0, 0.95, 0.7, 0.8), 3.4 * m, true)
	if CData.SEA_LANES.is_empty():
		return
	var tbl := MapView.table_on()
	for id in CLanes.count():
		if not CLanes.at_war(state, id):
			continue
		var wp := MapView.lane_poly(id)
		if wp.size() < 2:
			continue
		var wl: PackedVector2Array = xform * wp
		var wd := MapView.dash_polyline(wl, MapView.lane_dash(tbl), MapView.lane_gap(tbl))
		draw_war_dashes(_ci, wd, tbl)
	var rt := CLanes.raiders(state)
	for id in CLanes.count():
		var ri := raided_info(id, rt)
		if ri.is_empty():
			continue
		var poly2 := MapView.lane_poly(id)
		var pl2: PackedVector2Array = xform * poly2
		var dashes := MapView.dash_polyline(pl2, 9.0 * m, 6.0 * m)
		_ci.draw_multiline(dashes, Color(0, 0, 0, 0.55), 6.0 * m, true)
		_ci.draw_multiline(dashes, COL_RAID, 3.4 * m, true)
		var mid := pl2[pl2.size() / 2]
		var fs := int(round(12 * maxf(m, 0.8)))
		var txt := "raided"
		var tcol := Color(1, 0.92, 0.85)
		if bool(ri["seen"]):
			txt = "raided by %s" % str(CData.FACTIONS[int(ri["f"])]["adj"])
			tcol = CData.faction_color(int(ri["f"])).lightened(0.55)
		var tw := text_w(txt, fs)
		_ci.draw_rect(Rect2(mid - Vector2(tw * 0.5 + 6.0, fs * 0.5 + 3.0), Vector2(tw + 12.0, fs + 6.0)), Color(0.08, 0.03, 0.03, 0.92))
		_ci.draw_rect(Rect2(mid - Vector2(tw * 0.5 + 6.0, fs * 0.5 + 3.0), Vector2(tw + 12.0, fs + 6.0)), COL_RAID, false, 1.4)
		put(_ci, mid + Vector2(-tw * 0.5, fs * 0.38), txt, fs, tcol)


## The dashes (screen px, cut as MapView cuts the pale ones) of a lane at war: dull dark red-brown, bolder than the pale.
static func draw_war_dashes(ci, dashes: PackedVector2Array, tbl: bool) -> void:
	if dashes.size() < 2:
		return
	var w := (MapView.LANE_TABLE_W if tbl else MapView.LANE_W) * 2.4
	ci.draw_multiline(dashes, Color(0, 0, 0, 0.45), w + 1.8, true)
	ci.draw_multiline(dashes, COL_LANE_WAR, w, true)


## Lane id when it is raided now and the player is told (an owner of its ports, the raider's team, or sees the raider):
## {"f" raider faction, "fleet" its fleet, "seen" the raider is in sight}; {} otherwise. `rt`: CLanes.raiders(state).
func raided_info(id: int, rt: Dictionary) -> Dictionary:
	if not rt.has(id) or id >= CLanes.count():
		return {}
	var ls := CLanes.lane_state(state, id, rt)
	if int(ls["cuta"]) + int(ls["cutb"]) <= 0:
		return {}
	var fl: Dictionary = rt[id]
	var seen := FogView.fleet_seen(state, fl)
	var told: bool = player < 0 or CState.same_team(state, player, int(ls["oa"])) or CState.same_team(state, player, int(ls["ob"])) \
			or CState.same_team(state, player, int(ls["rf"])) or seen
	if not told or MapView.lane_poly(id).size() < 2:
		return {}
	return {"f": int(ls["rf"]), "fleet": fl, "seen": seen}


## The raiding fleets' ids (fleets named by raided_info), for the "raider" tag on their pennants.
func raider_fleet_ids() -> Dictionary:
	var out := {}
	if CData.SEA_LANES.is_empty() or not state.has("fleets"):
		return out
	var rt := CLanes.raiders(state)
	for id in rt:
		if not raided_info(int(id), rt).is_empty():
			out[int((rt[id] as Dictionary)["id"])] = true
	return out


## Lanes that explain themselves on a tap: raided (told) or at war.
func lane_at_info(p: Vector2) -> int:
	var ids: Array = []
	var rt := CLanes.raiders(state)
	for id in CLanes.count():
		if CLanes.at_war(state, id) or not raided_info(id, rt).is_empty():
			ids.append(id)
	return lane_at(p, ids)


## (N2b) A hurricane at p (screen) of radius rad: a pale disc with three
## spiral arms turning with t (seconds) round a dark eye.
static func draw_storm(ci, p: Vector2, rad: float, t: float, m: float) -> void:
	ci.draw_circle(p, rad, Color(0.82, 0.86, 0.92, 0.16))
	ci.draw_arc(p, rad, 0, TAU, 40, Color(0.92, 0.94, 1.0, 0.35), 1.5 * m, true)
	for arm in 3:
		var pts := PackedVector2Array()
		for i in 22:
			var f := float(i) / 21.0
			var ang := -t * 1.4 + arm * TAU / 3.0 + f * 3.4
			pts.append(p + Vector2(cos(ang), sin(ang)) * rad * (0.12 + 0.88 * f))
		ci.draw_polyline(pts, Color(0.1, 0.12, 0.18, 0.45), 6.0 * m, true)
		ci.draw_polyline(pts, Color(0.95, 0.97, 1.0, 0.85), 3.0 * m, true)
	ci.draw_circle(p, maxf(rad * 0.1, 3.0 * m), Color(0.08, 0.1, 0.16, 0.9))


## (N2b) A storm's forecast cone: the hull of its disc now and at the ends
## of the two tracks it may take (screen points a, b1, b2; radius rad).
static func draw_cone(ci, a: Vector2, b1: Vector2, b2: Vector2, rad: float, m: float) -> void:
	var pts := PackedVector2Array()
	for c in [a, b1, b2]:
		for i in 20:
			pts.append((c as Vector2) + Vector2(cos(TAU * i / 20.0), sin(TAU * i / 20.0)) * rad)
	var hull := Geometry2D.convex_hull(pts)
	if hull.size() >= 3:
		ci.draw_colored_polygon(hull, Color(1.0, 0.5, 0.2, 0.2))
		for k in hull.size() - 1:
			ci.draw_dashed_line(hull[k], hull[k + 1], Color(1.0, 0.6, 0.3, 0.85), 2.0 * m, 9.0, true, true)
	for b in [b1, b2]:
		ci.draw_dashed_line(a, b, Color(1.0, 0.75, 0.45, 0.7), 1.6 * m, 6.0, true, true)


## (N2b) A wreck at p: a broken mast and yard out of the water, a gold dot
## when treasure went down with her.
static func draw_wreck(ci, p: Vector2, gold: bool, m: float) -> void:
	var d := Vector2(3.0, -11.0) * m
	ci.draw_arc(p + Vector2(0, 1.5 * m), 7.0 * m, 0.2, PI - 0.2, 10, Color(0.05, 0.08, 0.12, 0.6), 2.0 * m, true)
	ci.draw_line(p, p + d, Color(0, 0, 0, 0.85), 4.0 * m, true)
	ci.draw_line(p, p + d, Color(0.55, 0.38, 0.2), 2.2 * m, true)
	var y0 := p + d * 0.7
	ci.draw_line(y0 + Vector2(-5.0, 1.5) * m, y0 + Vector2(5.0, -1.5) * m, Color(0, 0, 0, 0.85), 3.4 * m, true)
	ci.draw_line(y0 + Vector2(-5.0, 1.5) * m, y0 + Vector2(5.0, -1.5) * m, Color(0.55, 0.38, 0.2), 1.8 * m, true)
	if gold:
		ci.draw_circle(p + Vector2(-5.0, 1.0) * m, 3.0 * m, Color(0, 0, 0, 0.8))
		ci.draw_circle(p + Vector2(-5.0, 1.0) * m, 2.0 * m, Color(1.0, 0.82, 0.25))


## (N2b) Map point of a storm's centre (centi-cells).
static func storm_point(px: int, py: int) -> Vector2:
	var cp := float(CGrid.cell_px())
	return Vector2(px / 100.0, py / 100.0) * cp


func _draw_storms(m: float) -> void:
	var font := ThemeDB.fallback_font
	var cp := float(CGrid.cell_px())
	var tt := SeaWaves.t if SeaWaves.t > 0.0 else pulse
	for s in CStorm.storms(state):
		var a := to_screen(storm_point(int(s["px"]), int(s["py"])))
		var rad := float(s["r"]) * cp * zoom
		var b1: Array = CStorm.next_point(s, int(s["h"]))
		var b2: Array = CStorm.next_point(s, int(s["h"]) + 1)
		var trk: Array = s.get("tr", [])
		if trk.size() > 1:
			for k in trk.size() - 1:
				var p0 := to_screen(cell_point(CGrid.at(int(trk[k][0]), int(trk[k][1]))))
				var p1 := to_screen(cell_point(CGrid.at(int(trk[k + 1][0]), int(trk[k + 1][1]))))
				_ci.draw_dashed_line(p0, p1, Color(0.9, 0.92, 1.0, 0.55), 2.0 * m, 4.0, true, true)
		draw_cone(_ci, a, to_screen(storm_point(int(b1[0]), int(b1[1]))), to_screen(storm_point(int(b2[0]), int(b2[1]))), rad, m)
		draw_storm(_ci, a, rad, tt, m)
		var t1 := "Hurricane %s" % str(s["nm"])
		var fs := int(round(14 * maxf(m, 0.8)))
		var tw := font.get_string_size(t1, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var tp := a + Vector2(-tw * 0.5, -rad - 6.0)
		_ci.draw_string_outline(font, tp, t1, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(0, 0, 0, 0.8))
		_ci.draw_string(font, tp, t1, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1.0, 0.8, 0.6))
		var mid := (to_screen(storm_point(int(b1[0]), int(b1[1]))) + to_screen(storm_point(int(b2[0]), int(b2[1])))) * 0.5
		var t2 := "next turn"
		var fs2 := int(round(12 * maxf(m, 0.8)))
		var tw2 := font.get_string_size(t2, HORIZONTAL_ALIGNMENT_LEFT, -1, fs2).x
		_ci.draw_string_outline(font, mid + Vector2(-tw2 * 0.5, 4), t2, HORIZONTAL_ALIGNMENT_LEFT, -1, fs2, 4, Color(0, 0, 0, 0.75))
		_ci.draw_string(font, mid + Vector2(-tw2 * 0.5, 4), t2, HORIZONTAL_ALIGNMENT_LEFT, -1, fs2, Color(1.0, 0.7, 0.45))


func _draw_wrecks(m: float) -> void:
	var font := ThemeDB.fallback_font
	for w in state.get("wrecks", []):
		var c := CGrid.at(int(w[0]), int(w[1]))
		if c < 0 or not FogView.cell_seen(c):
			continue
		var p := to_screen(cell_point(c))
		draw_wreck(_ci, p, int(w[3]) > 0, m)
		if zoom >= 1.2 and str(w[4]) != "":
			var t := str(w[4])
			var fs := 11
			var tw := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			_ci.draw_string_outline(font, p + Vector2(-tw * 0.5, 14.0 * m), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 3, Color(0, 0, 0, 0.75))
			_ci.draw_string(font, p + Vector2(-tw * 0.5, 14.0 * m), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.95, 0.85, 0.6))


## The treasure mark on a flota ship (a gold coin with a dark edge).
static func draw_treasure(ci, p: Vector2, m: float) -> void:
	ci.draw_circle(p, 6.5 * m, Color(0, 0, 0, 0.85))
	ci.draw_circle(p, 5.0 * m, Color(1.0, 0.82, 0.25))
	ci.draw_circle(p, 2.2 * m, Color(0.75, 0.55, 0.1))


## The flota's course: from each flota fleet along its voyage (the route
## the rules keep for it) to the meeting port, then by sea to the exit
## (searched once for a galleon, kept for the session), dashed gold; a gold
## arrow at the exit.
static var _home_leg: Array = []  # map points from the meeting port to the exit


func _flota_course(fpos: Dictionary) -> void:
	var ex := CSea.exit_cell()
	if ex < 0:
		return
	var any := false
	var m := mk()
	var gold := Color(1.0, 0.82, 0.3, 0.85)
	var meet := CSea.meet_cell()
	if _home_leg.is_empty() and meet >= 0:
		var probe := {"id": -1, "f": 0, "x": CGrid.cx(meet), "y": CGrid.cy(meet), "ships": [{"t": "galleon", "h": 100, "c": 100}],
			"carry": [], "moved": 0}
		var p := CFleet.find_path(probe, ex, PackedByteArray(), false, 30, 40000)
		_home_leg = [cell_point(meet)]
		for c in p.get("path", []):
			_home_leg.append(cell_point(int(c)))
	for fl in state["fleets"]:
		if not CSea.is_flota(fl) or not fpos.has(int(fl["id"])):
			continue
		any = true
		var pts := PackedVector2Array([fpos[int(fl["id"])]])
		for c in fl.get("route", []):
			pts.append(to_screen(cell_point(int(c))))
		if int(fl["flota"]) <= 1:
			for q in _home_leg:
				pts.append(to_screen(q))
		else:
			pts.append(to_screen(cell_point(ex)))
		# Thin the cell steps to every third point (a smoother dash).
		var thin := PackedVector2Array()
		for k in pts.size():
			if k % 3 == 0 or k == pts.size() - 1:
				thin.append(pts[k])
		for k in thin.size() - 1:
			_ci.draw_dashed_line(thin[k], thin[k + 1], Color(0, 0, 0, 0.45), 4.0 * m, 10.0, true, true)
		for k in thin.size() - 1:
			_ci.draw_dashed_line(thin[k], thin[k + 1], gold, 2.2 * m, 10.0, true, true)
	if not any:
		return
	var e := to_screen(cell_point(ex))
	var tip := e + Vector2(0, -16.0 * m)
	_ci.draw_line(e, tip, Color(0, 0, 0, 0.8), 5.0 * m, true)
	_ci.draw_line(e, tip, gold, 3.0 * m, true)
	_ci.draw_colored_polygon(PackedVector2Array([tip + Vector2(0, -8.0 * m), tip + Vector2(6.0 * m, 0), tip + Vector2(-6.0 * m, 0)]), gold)
	var font := ThemeDB.fallback_font
	var fs := 13
	var tp := e + Vector2(10.0 * m, 4.0)
	_ci.draw_string_outline(font, tp, "Flota: to Spain", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(0, 0, 0, 0.8))
	_ci.draw_string(font, tp, "Flota: to Spain", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, gold)


## An army banner at c (size ARMY_W x ARMY_H times m): a shield in the
## faction colour (the same colour as its settlements and land band) with a
## dark edge (inside it a white rim: a player's army), the unit count
## (outlined so it reads on any faction colour), the strength bar (men /
## full strength, frac), the selection frame (glow > 0), versions 1-5 the
## grey "moved" dot (version 6 shows marches as paths and has the stance
## badge there). Returns the banner's rect.
static func draw_banner(ci, c: Vector2, col: Color, m: float, human: bool, count: int, frac: float,
		glow: float = 0.0, moved: bool = false, emblem: String = "") -> Rect2:
	var rect := Rect2(c - Vector2(ARMY_W, ARMY_H) * 0.5 * m, Vector2(ARMY_W, ARMY_H) * m)   # (the tap area: unchanged)
	var sel := glow > 0.0
	var sm := maxf(m, 0.8)   # the standard keeps a readable size when zoomed out (the hit rect shrinks, it does not)
	var o := c + Vector2(0, -3.0 * sm if sel else 0.0)   # the selected standard lifts a little
	var rim := COL_SELECTED if sel else Color(1, 1, 1)
	# The pole, then the swallow-tailed pennant in the faction colour with the crest (a glyph on a batch).
	_glyph(ci, ["std", col, sm, human, sel, emblem], o, func(gb, q: Vector2): _standard(gb, q, col, sm, human, sel, rim, emblem))
	# The strength on a parchment roundel with an ink rim at the pole's foot.
	var rc := Vector2(o.x - 9.0 * sm + 4.0 * sm, o.y + 6.0 * sm)
	var rr := 9.0 * sm
	var n := str(count)
	var afs := int(round(14 * maxf(m, 0.75)))
	if text_w(n, afs) > rr * 1.75:
		afs = maxi(int(afs * rr * 1.75 / text_w(n, afs)), 9)
	_glyph(ci, ["rnd", rr, human or sel, rim, n, afs], rc, func(gb, q: Vector2): _roundel(gb, q, rr, human or sel, rim, n, afs))
	var by := rect.end.y + 5.0 * m
	ci.draw_rect(Rect2(rect.position.x, by, rect.size.x, 4 * m), Color(0, 0, 0, 0.7))
	ci.draw_rect(Rect2(rect.position.x, by, rect.size.x * frac, 4 * m), BAR_GOOD if frac > 0.6 else BAR_LOW)
	if moved:
		ci.draw_circle(rect.position + Vector2(rect.size.x, 0), 3.5, COL_MOVED)
	return rect


## The standard's pole, finial and pennant with the crest, the standard at o (draw_banner).
static func _standard(ci, o: Vector2, col: Color, sm: float, human: bool, sel: bool, rim: Color, emblem: String) -> void:
	var pole_x := o.x - 9.0 * sm
	var top := o.y - 17.0 * sm
	ci.draw_line(Vector2(pole_x, top - 4.0 * sm), Vector2(pole_x, o.y + 8.0 * sm), COL_OUTLINE, 3.2, true)
	ci.draw_line(Vector2(pole_x, top - 3.0 * sm), Vector2(pole_x, o.y + 8.0 * sm), Color(0.55, 0.42, 0.26), 1.5, true)
	ci.draw_circle(Vector2(pole_x, top - 4.0 * sm), 2.0, COL_OUTLINE)
	ci.draw_circle(Vector2(pole_x, top - 4.0 * sm), 1.0, Color(0.85, 0.7, 0.35))
	var pw := 27.0 * sm
	var pts := PackedVector2Array([Vector2(pole_x, top), Vector2(pole_x + pw, top), Vector2(pole_x + pw - 6.0 * sm, top + 8.0 * sm),
		Vector2(pole_x + pw, top + 16.0 * sm), Vector2(pole_x, top + 16.0 * sm)])
	ci.draw_colored_polygon(pts, col)
	var outline := pts.duplicate()
	outline.append(pts[0])
	ci.draw_polyline(outline, COL_OUTLINE, 3.5 if (human or sel) else 1.8, true)
	if human or sel:
		ci.draw_polyline(outline, rim, 1.8, true)
	if emblem != "" and FactionEmblem.has(emblem):
		var es := 13.0 * sm
		FactionEmblem.draw(ci, emblem, Rect2(Vector2(pole_x + 3.0 * sm, top + 8.0 * sm - es * 0.5), Vector2(es, es)))


## A count (n, font size fs) on a parchment roundel of radius rr with an ink rim (and a rim of colour `rim`) at rc.
static func _roundel(ci, rc: Vector2, rr: float, rimmed: bool, rim: Color, n: String, fs: int) -> void:
	ci.draw_circle(rc, rr + 1.6, COL_OUTLINE)
	if rimmed:
		ci.draw_arc(rc, rr + 1.2, 0, TAU, 24, rim, 1.4, true)
	ci.draw_circle(rc, rr, Color(0.93, 0.87, 0.7))
	put(ci, rc + Vector2(-text_w(n, fs) * 0.5, fs * 0.34), n, fs, Color(0.1, 0.06, 0.03))


## What f(ci, p) draws at p: on an OvBatch a glyph kept under `key` (everything the drawing depends on but the place:
## drawn once, then stamped; ov_batch.gd), on a CanvasItem the drawing itself.
static func _glyph(ci, key: Array, p: Vector2, f: Callable) -> void:
	if ci is OvBatch:
		(ci as OvBatch).glyph(key, p, f)
	else:
		f.call(ci, p)


## Afloat (2026-10-23): a small canoe under the banner of an amphibious army on the water.
static func draw_canoe(ci, rect: Rect2, m: float) -> void:
	var c := Vector2(rect.get_center().x, rect.end.y + 5.0 * m)
	var hull := PackedVector2Array([c + Vector2(-11, -2) * m, c + Vector2(-5, 2.5) * m, c + Vector2(5, 2.5) * m,
		c + Vector2(11, -2) * m, c + Vector2(0, -0.5) * m])
	ci.draw_colored_polygon(hull, Color(0.45, 0.3, 0.16))
	var ho := hull.duplicate()
	ho.append(hull[0])
	ci.draw_polyline(ho, Color(0, 0, 0, 0.85), 1.4, true)
	ci.draw_line(c + Vector2(-3, -5) * m, c + Vector2(4, 4) * m, Color(0.85, 0.75, 0.55), 1.5, true)   # the paddle


## Inside the walls: a small crenellated tower on the banner's corner.
static func draw_tower(ci, rect: Rect2, m: float) -> void:
	var tw2 := 8.0 * m
	var tp := rect.position + Vector2(-tw2 * 0.6, -tw2 * 0.4)
	var stone := Color(0.85, 0.8, 0.7)
	ci.draw_rect(Rect2(tp - Vector2(1, 1), Vector2(tw2, tw2 * 1.1) + Vector2(2, 2)), Color(0.05, 0.05, 0.05))
	ci.draw_rect(Rect2(tp, Vector2(tw2, tw2 * 1.1)), stone)
	for k in 3:
		ci.draw_rect(Rect2(tp + Vector2(tw2 * 0.38 * k, -tw2 * 0.25), Vector2(tw2 * 0.24, tw2 * 0.25)), stone)


## Version 6: a letter on the banner's top right for a stance other than
## the default (F forced march, D fortified, R raiding).
static func draw_stance(ci, rect: Rect2, st_v: int) -> void:
	if not STANCE_LETTERS.has(st_v):
		return
	var txt := str(STANCE_LETTERS[st_v])
	var c := rect.position + Vector2(rect.size.x, 0)
	ci.draw_circle(c, 7.0, Color(0, 0, 0, 0.85))
	ci.draw_circle(c, 6.0, STANCE_COLS[st_v])
	var font := ThemeDB.fallback_font
	var tw := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
	ci.draw_string(font, c + Vector2(-tw * 0.5, 4), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color.WHITE)


## Version 5: one hop of a march (s0 -> e0): solid this turn, dotted after.
static func draw_hop(ci, s0: Vector2, e0: Vector2, col: Color, this_turn: bool, m: float) -> void:
	if this_turn:
		ci.draw_line(s0, e0, Color(0, 0, 0, 0.6), (PATH_W_NOW + 3.0) * m, true)
		ci.draw_line(s0, e0, col, PATH_W_NOW * m, true)
	else:
		ci.draw_dashed_line(s0, e0, Color(0, 0, 0, 0.55), (PATH_W_LATER + 3.0) * m, PATH5_DASH, true)
		ci.draw_dashed_line(s0, e0, col.darkened(0.05), PATH_W_LATER * m, PATH5_DASH, true)


## Versions 1-4: a planned move as an arrow.
static func draw_arrow(ci, from: Vector2, to: Vector2, col: Color) -> void:
	var d := to - from
	var ln := d.length()
	if ln < 4.0:
		return
	var u := d / ln
	var tip := to - u * 14.0
	var start := from + u * 14.0
	var nrm := Vector2(-u.y, u.x)
	ci.draw_line(start, tip, Color(0, 0, 0, 0.6), 7.0, true)
	ci.draw_line(start, tip, col, 4.0, true)
	var head := PackedVector2Array([tip + u * 12.0, tip + nrm * 8.0, tip - nrm * 8.0])
	ci.draw_colored_polygon(head, col)
	var ho := head.duplicate()
	ho.append(head[0])
	ci.draw_polyline(ho, Color(0, 0, 0, 0.6), 1.5, true)


# ------------------------------------------------------------ the map ---

## Version 6 replay: a faint line behind each army on its way.
func _draw_trails() -> void:
	for a in state["armies"]:
		var id := int(a["id"])
		if not replay_trail.has(id) or not replay_pos.has(id):
			continue
		var pts := PackedVector2Array()
		for q in replay_trail[id]:
			pts.append(to_screen(q))
		pts.append(to_screen(replay_pos[id]))
		if pts.size() >= 2:
			draw_trail(_ci, pts, CData.faction_color(int(a["f"])))


## Version 6: support (yellow) and attack (red) lines of the selected army.
func _draw_links(pos: Dictionary) -> void:
	for ln in links:
		if not pos.has(int(ln[0])) or not pos.has(int(ln[1])):
			continue
		draw_link(_ci, pos[int(ln[0])], pos[int(ln[1])], int(ln[2]))


## The settlement army `id` stands inside (-1 none, or the army is replayed).
func _inside_site(id: int) -> int:
	if replay_pos.has(id):
		return -1
	var a := CState.army(state, id)
	if a.is_empty() or not CRules.inside(state, a):
		return -1
	return CGrid.site_region(CState.cell(a))


## Version 6: a planned path along cell centres: solid this turn, dashed
## beyond, a ring where this turn ends, the intent at the end.
func _path6(pth: Dictionary, pos: Dictionary) -> void:
	var pts: Array = pth["pts"]
	if pts.size() < 2:
		return
	var id := int(pth["army"])
	var kind := str(pth.get("kind", "move"))
	var col := path_color(kind, str(pth.get("caption", "")))
	var m := mk()
	var sp: Array = []
	for k in pts.size():
		sp.append(to_screen(pts[k]))
	var home := _inside_site(id)
	if home >= 0:
		sp[0] = to_screen(site_point(home))   # (an army in a town: the path leads straight out of it)
	elif pos.has(id) and not pth.has("drag"):
		sp[0] = pos[id]
	var now := int(pth["now"])
	for k in pts.size() - 1:
		var a: Vector2 = sp[k]
		var b: Vector2 = sp[k + 1]
		if a.distance_to(b) < 1.0:
			continue
		draw_path_step(_ci, a, b, col, k < now, m)
	if now > 0 and now < pts.size() - 1:
		draw_turn_end(_ci, sp[now], col, m)
	if int(pth.get("board", 0)) != 0:
		_ci.draw_circle(sp[-1], 9.0 * m, Color(0, 0, 0, 0.6))
		draw_boat(_ci, sp[-1], COL_BOARD, m)
	_tips.append([sp[-1], kind, col, str(pth.get("caption", ""))])
	if int(pth.get("trespass", 0)) != 0:
		_tips.append([sp[-1] + Vector2(12, -12) * m, "trespass", COL_TRESPASS, ""])   # (a march into land at peace: warned at its end)


## A boarding cell: a rounded teal outline over the cell with a small boat at its centre.
func _draw_board_cell(c: int) -> void:
	var m := mk()
	var half := float(CGrid.cell_px()) * zoom * 0.5 - 1.0
	var ctr := to_screen(cell_point(c))
	var r := Rect2(ctr - Vector2(half, half), Vector2(half, half) * 2.0)
	_ci.draw_rect(r, Color(COL_BOARD.r, COL_BOARD.g, COL_BOARD.b, 0.16), true)
	_ci.draw_rect(r, Color(0, 0, 0, 0.45), false, 3.0 * m)
	_ci.draw_rect(r, Color(COL_BOARD.r, COL_BOARD.g, COL_BOARD.b, 0.9), false, 1.6 * m)
	draw_boat(_ci, ctr, COL_BOARD, m * 0.8)


## A small boat glyph (hull and a sail) at p.
static func draw_boat(ci, p: Vector2, col: Color, m: float) -> void:
	var hull := PackedVector2Array([p + Vector2(-6, 1) * m, p + Vector2(6, 1) * m, p + Vector2(3.5, 5) * m, p + Vector2(-3.5, 5) * m])
	var sail := PackedVector2Array([p + Vector2(0.5, -7) * m, p + Vector2(5, 0) * m, p + Vector2(0.5, 0) * m])
	for poly in [hull, sail]:
		var o := PackedVector2Array(poly)
		o.append(o[0])
		ci.draw_polyline(o, Color(0, 0, 0, 0.7), 3.0, true)
	ci.draw_colored_polygon(hull, col)
	ci.draw_colored_polygon(sail, Color(0.97, 0.97, 0.9))


## A planned voyage: this turn's part solid, later turns dashed, a ring
## where this turn ends, swords for an attack, an anchor-like dot for a landing.
func _fleet_path(fp: Dictionary, fpos: Dictionary) -> void:
	var id := int(fp["fleet"])
	var cells: Array = fp["path"]
	if not fpos.has(id) or cells.is_empty():
		return
	var m := mk()
	var col := COL_ATTACK if int(fp["attack"]) != 0 else Color(0.45, 0.85, 1.0)
	var prev: Vector2 = fpos[id]
	var end_now := Vector2.INF
	for i in cells.size():
		var q := to_screen(cell_point(int(cells[i])))
		var now := int(fp["t"][i]) == 0
		draw_path_step(_ci, prev, q, col, now, m)
		if now:
			end_now = q
		prev = q
	if end_now != Vector2.INF and end_now != prev:
		draw_turn_end(_ci, end_now, col, m)
	if int(fp["attack"]) != 0:
		draw_intent(_ci, prev, "attack", col, m)
	elif int(fp.get("join", 0)) != 0:
		draw_merge_glyph(_ci, prev, 0, m)
	elif int(fp["land"]) != 0:
		_ci.draw_circle(prev, 7.0 * m, Color(0, 0, 0, 0.7))
		_ci.draw_circle(prev, 5.0 * m, Color(0.95, 0.85, 0.4))


## A fleet: a ship in the faction's colour riding the waves (it bobs and
## rolls with SeaWaves at its spot), the number of ships on its pennant, a
## soldier dot when troops are aboard, a white rim for a player's.
func _fleet_marker(c: Vector2, fl: Dictionary) -> void:
	var f := int(fl["f"])
	var m := mk()
	var col := CData.faction_color(f)
	var mp := cell_point(CFleet.cell(fl))
	var tt := SeaWaves.t if SeaWaves.t > 0.0 else pulse
	var a := clampf(SeaWaves.amp(mp), 0.25, 1.0)
	var bob := SeaWaves.height(mp, tt) * a * 2.2 * m
	var n := SeaWaves.normal(mp, tt)
	var roll := clampf(n.x * a * 0.9, -0.22, 0.22)
	var human := CState.is_human(state, f)
	var sel := int(fl["id"]) == selected_fleet
	var xf := Transform2D(roll, c + Vector2(0, bob))
	var s := FLEET_W * 0.5 * m
	if sel:
		_ci.draw_circle(c, s * 1.45 + 2.0 * sin(pulse * 5.0), Color(COL_SELECTED, 0.55))
	if not Minis.on_ships:
		# A sail glyph: a triangular sail in the faction colour on a dark hull.
		var hull := PackedVector2Array([Vector2(-s, 0.15 * s), Vector2(s, 0.15 * s), Vector2(0.62 * s, 0.62 * s), Vector2(-0.7 * s, 0.62 * s)])
		var sail := PackedVector2Array([Vector2(0.05 * s, -1.0 * s), Vector2(0.8 * s, 0.05 * s), Vector2(0.05 * s, 0.05 * s)])
		var jib := PackedVector2Array([Vector2(-0.08 * s, -0.62 * s), Vector2(-0.66 * s, 0.05 * s), Vector2(-0.08 * s, 0.05 * s)])
		var shadow := Transform2D(roll, c + Vector2(1.5, 2.0 + bob))
		_ci.draw_colored_polygon(shadow * hull, Color(0, 0, 0, 0.3))
		var hw: PackedVector2Array = xf * hull
		_ci.draw_colored_polygon(hw, Color(0.2, 0.14, 0.09))
		var ho := hw.duplicate()
		ho.append(hw[0])
		_ci.draw_polyline(ho, COL_OUTLINE, 2.4 if human else 1.6, true)
		if human:
			_ci.draw_polyline(ho, Color(1, 1, 1), 1.2, true)
		_ci.draw_line(xf * Vector2(0, -1.05 * s), xf * Vector2(0, 0.15 * s), COL_OUTLINE, 1.6, true)
		for poly in [sail, jib]:
			var pw: PackedVector2Array = xf * poly
			_ci.draw_colored_polygon(pw, col if poly == sail else col.lightened(0.25))
			var o := pw.duplicate()
			o.append(pw[0])
			_ci.draw_polyline(o, COL_OUTLINE, 1.4, true)
	elif human:
		_ci.draw_arc(c + Vector2(0, 2), s * 0.8, 0, TAU, 20, Color(1, 1, 1, 0.85), 1.6, true)
	# The ship count on a parchment roundel (as the armies').
	var txt := str((fl["ships"] as Array).size())
	var fs := int(round(14 * maxf(m, 0.75)))
	var rr := 8.5 * maxf(m, 0.8)
	var tp := xf * Vector2(0, -1.05 * s - (Minis.label_lift() * 0.5 if Minis.on_ships else 0.0)) + Vector2(4.0 * m + rr, fs * 0.2 - rr * 0.6)
	_glyph(_ci, ["frnd", rr, human, txt, fs], tp, func(gb, q: Vector2): _fleet_roundel(gb, q, rr, human, txt, fs))
	tp += Vector2(-rr, rr * 0.4)
	if _raider_ids.has(int(fl["id"])):   # (lanes) the fleet raiding a lane
		var rfs := int(round(10 * maxf(m, 0.8)))
		var rw := text_w("raider", rfs)
		var rp := tp + Vector2(-1.0, rfs + 4.0)
		_ci.draw_rect(Rect2(rp + Vector2(-2, -rfs + 1), Vector2(rw + 4, rfs + 3)), Color(0.5, 0.06, 0.04, 0.92))
		put(_ci, rp, "raider", rfs, Color(1, 0.9, 0.85))
	if not (fl["carry"] as Array).is_empty():
		var dp := xf * Vector2(-0.35 * s, 0.38 * s)
		_ci.draw_circle(dp, 4.5 * m, Color(0, 0, 0, 0.85))
		_ci.draw_circle(dp, 3.2 * m, Color(1, 0.95, 0.75))
	var capt := CCaptain.of_fleet(state, int(fl["id"])) if state.has("captains") else {}
	if not capt.is_empty() and zoom >= 0.45:
		var tn := CCaptain.tier_name(int(capt["fame"]))
		var ct := str(capt["nm"]) + (" (%s)" % tn if tn != "" else "")
		var cfs := int(round(12 * maxf(m, 0.8)))
		var cw := text_w(ct, cfs)
		var cpp := c + Vector2(-cw * 0.5, s * 0.62 + cfs + 4.0)
		put(_ci, cpp, ct, cfs, Color(1.0, 0.55, 0.45) if CCaptain.tier(int(capt["fame"])) >= 2 else col.lightened(0.6), 4, Color(0, 0, 0, 0.85))
	if CSea.treasure(fl) > 0:
		draw_treasure(_ci, xf * Vector2(-0.62 * s, -0.35 * s), m)
		var ft := "Flota"
		var fw := text_w(ft, fs)
		var fp := c + Vector2(-fw * 0.5, s * 0.62 + fs + 4.0)
		put(_ci, fp, ft, fs, Color(1.0, 0.85, 0.35), 4, Color(0, 0, 0, 0.8))


## The ship count on a fleet's roundel, its text's baseline origin at tp (_fleet_marker).
static func _fleet_roundel(ci, tp: Vector2, rr: float, human: bool, txt: String, fs: int) -> void:
	ci.draw_circle(tp + Vector2(0, -fs * 0.34), rr + 1.6, COL_OUTLINE)
	if human:
		ci.draw_arc(tp + Vector2(0, -fs * 0.34), rr + 1.2, 0, TAU, 24, Color(1, 1, 1), 1.3, true)
	ci.draw_circle(tp + Vector2(0, -fs * 0.34), rr, Color(0.93, 0.87, 0.7))
	put(ci, tp + Vector2(-text_w(txt, fs) * 0.5, 0), txt, fs, Color(0.1, 0.06, 0.03))


## A path's caption ("Merge into army (5 units)") above its end.
func _caption(p: Vector2, text: String, col: Color) -> void:
	var font := ThemeDB.fallback_font
	var fs := 14
	var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var tp := p + Vector2(-tw * 0.5, -ARMY_H * mk() - 6.0)
	_ci.draw_rect(Rect2(tp + Vector2(-5, -fs), Vector2(tw + 10, fs + 7)), Color(0, 0, 0, 0.7))
	_ci.draw_string(font, tp, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col.lightened(0.3))


func _army_marker(c: Vector2, a: Dictionary) -> void:
	var f := int(a["f"])
	var m := mk()
	var human := CState.is_human(state, f)
	var men := 0
	var full := 0
	for u in a["units"]:
		men += int(u["n"])
		full += preload("res://sim/unit_types.gd").size_of(CState.unit_type(u))
	var frac := clampf(float(men) / maxf(full, 1), 0.0, 1.0)
	var glow := 1.0 if int(a["id"]) == selected_army else 0.0   # (the selected standard lifts and has a gold rim; its halo pulses: its own part)
	var rect := draw_banner(_ci, c, CData.faction_color(f), m, human, CState.unit_count(a), frac, glow,
		int(a["moved"]) != 0 and human and not grid, CData.FACTIONS[f]["key"] if f >= 0 else "")
	if grid:
		draw_stance(_ci, rect, CState.stance(a))
	if human and f == player and trespass_owner(state, f, int(a["r"])) >= 0:
		draw_intent(_ci, rect.position + Vector2(rect.size.x, 0), "trespass", COL_TRESPASS, m * 0.7)   # (standing in land at peace without passage)
	if (not grid and int(a.get("stance", 0)) == CData.STANCE_GARRISON) or (grid and CRules.inside(state, a)):
		draw_tower(_ci, rect, m)
	if grid and CRules.afloat(a):
		draw_canoe(_ci, rect, m)   # (amphibious, afloat on the coastal sea)


## A march: from the army's banner along the region sites; this turn's
## hops solid, later ones dotted, an arrowhead at the destination.
func _path(pth: Dictionary, pos: Dictionary) -> void:
	var id := int(pth["army"])
	var pts: Array = pth["pts"]
	if pts.size() < 2:
		return
	var col := COL_MOVE
	if siege_moves.has(id):
		col = COL_SIEGE
	elif attack_moves.has(id):
		col = COL_ATTACK
	var sp: Array = []
	for k in pts.size():
		sp.append(to_screen(pts[k]) + Vector2(0, 8))
	if pos.has(id):
		sp[0] = pos[id]
	var now := int(pth["now"])
	var m := mk()
	for k in pts.size() - 1:
		var a: Vector2 = sp[k]
		var b: Vector2 = sp[k + 1]
		var last := k == pts.size() - 2
		var d := b - a
		var ln := d.length()
		if ln < 4.0:
			continue
		var u := d / ln
		var s0 := a + u * (14.0 if k == 0 else 6.0)
		var e0 := b - u * (14.0 if last else 6.0)
		draw_hop(_ci, s0, e0, col, k < now, m)
		if not last:
			_ci.draw_circle(b, 3.5 * m, col if k < now else Color(col, 0.6))
		else:
			var tip := e0
			var nrm := Vector2(-u.y, u.x)
			var head := PackedVector2Array([tip + u * 10.0, tip + nrm * 7.0 - u * 2.0, tip - nrm * 7.0 - u * 2.0])
			_ci.draw_colored_polygon(head, col)
