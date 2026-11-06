extends Node2D
## World-space overlay: unit markers, the selected units' formations and
## orders, missile ranges and targets, and the live preview while the player
## draws a destination line (for one unit or a group).

const BattleSim := preload("res://sim/battle_sim.gd")
const MapGen := preload("res://sim/mapgen.gd")
const UT := preload("res://sim/unit_types.gd")
const OccView := preload("res://game/occupy_view.gd")
const Icons := preload("res://game/unit_icons.gd")
const UIIcons := preload("res://game/ui_icons.gd")
const WorksLayer := preload("res://game/works_layer.gd")
const SpriteAtlas := preload("res://game/sprite_atlas.gd")
const Quality := preload("res://game/quality.gd")
const LastSeen := preload("res://game/last_seen.gd")
const Marks := preload("res://game/tabletop_marks.gd")
const CData := preload("res://campaign/cdata.gd")
const BoardView := preload("res://game/board_view.gd")
const SiegeGearOb := preload("res://game/siege_gear_ob.gd")
const SoldierLayer := preload("res://game/soldier_layer.gd")
var _siege_ob := SiegeGearOb.new()
const Traits := preload("res://game/unit_traits.gd")
const UiScale := preload("res://game/ui_scale.gd")
## The sprite atlas (loaded, not preloaded: see soldier_layer.gd). Wagons
## (carts, wagons, their horses) are drawn from its shade sheet (step 1d
## props: fixed colours, no faction mask) by a child node under the
## overlay's own drawing, with mipmaps; without it, the code-drawn shapes.
const ATLAS_SHADE_PATH := "res://assets/sprites/atlas_shade.png"
const PROP_PX_PER_M := 24.0
## Marker radius in screen pixels (never below MARKER_MIN_R world pixels).
const MARKER_SCREEN_R := 11.0
const MARKER_MIN_R := 5.5
const M := 1024.0
## Standard: scale 1 is 29 px tall (the overworld's banner; about 28 at zoom 1), scaled with the zoom, never under 18 px.
const STD_MIN_SCALE := 0.62
const STD_MAX_SCALE := 2.0
## State tokens: diameter in screen px at zoom 1, scaled with the zoom, clamped.
const TOKEN_D := 14.0
const TOKEN_MIN := 12.0
const TOKEN_MAX := 28.0
const GROUP_GAP_M := 2.0   # metres left between units lined up by a drag

var sim
## The tabletop's tray layer (the formation quads the standards and tokens sit on) and the soldier layer (the unit's colour).
var trays
var soldiers
## Battle._card_states: the card strip's state list of a unit, [glyph, word] each (the tokens show the same).
var token_states := Callable()
var standards_us := 0
var _std_col: Array[Color] = []
var _std_emb: Array[String] = []
var _std_tex: Array = []
var _tok_at := PackedInt32Array()
var _tok_cache: Array = []   # microseconds the last standards-and-tokens pass cost (benchmarks)
var px_per_m: float = 10.0
var selected_units: Array[int] = []   # first = primary
var group_tags := {}                  # unit -> its control-group numbers ("2", "1 3", "1 2+"; view only): a tab on its marker
var zoom: float = 1.0
var show_all_orders := false   # draw every friendly unit's order footprint
var player_side := 0
var orders  # OrderPreview: predicted order state including not-yet-applied orders
# Cover and line of fire, second pass (2026-11-06; docs/design/ui.md "Cover chips and hittable marks"): view caches,
# each refreshed once a sim second (they read the sim, change nothing).
var _chip := {}        # unit -> [sim second, cover rating 0-2, threat bearing (sim angle), troop kind]
var _hit := {}         # source unit * 4096 + enemy -> [sim second, 1 hittable / 0 blocked]
var _ring := {}        # unit -> [sim second, cx, cy, PackedInt32Array radii per ring step (house cut)]
var _fsv := {}         # unit * 4096 + target -> [sim second, Vector3i]: the order preview's fire spot when the sim keeps none
var _dpr := 1.0        # window px per CSS px (UiScale), read once a second
var _dpr_ms := -100000

# Drag preview (world pixels), active when preview_on.
var preview_on := false
var preview_a := Vector2.ZERO
var preview_b := Vector2.ZERO
var preview_ok := false  # long enough to be a formation line
var preview_clamped := false  # pulled out to the selection's single-rank length (the line stops there)
## Deployment: a stakes line being dragged (preview_a -> preview_b).
var works_drag := false
## Mouse over the field (world px; x < 0: none): the wall stretch under it
## is highlighted while a unit that can man the walls is selected.
var hover_w := Vector2(-1, -1)
## Moves now add a waypoint (the Waypoints toggle, Shift with a mouse): the
## previews start from the end of each unit's chain.
var append_on := false
const COL_CHAIN := Color(0.6, 1.0, 0.6)          # a selected unit's waypoint chain (faint)
var _icon := PackedInt32Array()  # unit -> symbol id
## Matchup mark: the enemy unit under the pointer / finger while a unit is
## selected (-1 none) and the selected unit's matchup against it (1 / 0 / -1).
var match_u := -1
var match_v := 0
## The Occupy flow (game/battle.gd): the buildings the selection may be sent into (lit), the one shown
## (its sight fans, its places, a tip) and the tip's last line; the fan cache is per (building, range).
var occ_mode := false
## The ability chips' Use now pick (battle.gd): the enemy units that may be picked, ringed.
var target_lit: Array[int] = []
var occ_lit: Array[int] = []
var occ_focus := -1
var occ_range_m := 60.0
var occ_hint := ""
var _occ_fans := {}
var occ_fan_us := 0   # microseconds the last fan cost to build (tests, benchmarks)

const COL_SIDE := [Color(0.35, 0.6, 1.0), Color(1.0, 0.36, 0.28)]
const COL_FIRE := Color(1.0, 0.75, 0.25, 0.8)
const COL_ARC := Color(1.0, 0.85, 0.4, 0.5)
const FX_TICKS := 15.0   # stone impact marks last this many ticks
const COL_WITHDRAW := Color(0.85, 0.85, 1.0, 0.8)
const COL_BLOCKED := Color(1.0, 0.25, 0.2, 0.9)
const COL_UPHILL := Color(1.0, 0.62, 0.35)
const COL_DOWNHILL := Color(0.6, 1.0, 0.6)
const HINT_GRADE := 164   # slopes under 4% get no uphill / downhill hint
const RANGE_STEPS := 72   # height-adjusted range ring: points round the circle
const COL_WOODS := Color(0.85, 1.0, 0.35)
const COL_COVER := Color(0.55, 0.9, 0.45)  # own cover troops in cover (a leaf; filled: gone to ground)
const REVEAL_FX := 15     # ticks a "seen after hiding" ring spreads from a marker
const COL_BLOCK_CELL := Color(1.0, 0.35, 0.3, 0.7)
const COL_OCC := Color(1.0, 0.82, 0.30)           # an occupiable building, its fans
const COL_ROUTE := Color(1.0, 0.97, 0.78, 0.95)    # the street route a move will take (dotted)
const COL_NOWAY := Color(1.0, 0.3, 0.25, 0.95)     # ... none found
const FLASH_MS := 2500
const STRETCH_FLASH_MS := 900
const COL_WALL := Color(1.0, 0.92, 0.45)
const COL_STAIR := Color(0.45, 1.0, 0.95)


## Unit order field as the player last ordered it (pending orders included).
## Group move (three fingers / Alt+drag): destination footprints, each
## {unit, front (world px), face, files}; and a short label.
var ghosts: Array = []
var ghost_hint := ""
## Box select (mouse drag on empty ground): corners in world px.
var box_on := false
var box_a := Vector2.ZERO
var box_b := Vector2.ZERO
## A short message at a world point (gate taps): text, where, until (ms).
var _flash_text := ""
var _flash_at := Vector2.ZERO
var _flash_until := 0
## A tapped wall stretch lit for a moment (touch has no hover): -1 or index, until (ms).
var _stretch_flash := -1
var _stretch_until := 0


# View-only effects (fire and blast): no sim state, no hash. Missiles of the
# kinds that matter are followed from the sim's landing buckets; one that is
# gone landed at its aim point. The effects live on the view clock.
const FX_CAP := 64
const FX_FIRE := 1     # a fire missile: sparks, then smoke
const FX_BLAST := 2    # an explosive stone: flash, ring, lingering smoke
const FX_DUST := 3     # an ordinary stone: a puff
const FX_CHIP := 4     # a ball stopped by a wall, house or rock (phase C0): a pale flash, chips and a lingering dust cloud
const FX_RUIN := 5     # a wall stretch breached or a building fallen (destruction): a dust haze over it fading for 10 s
const FX_LIFE := [0.0, 2.0, 3.0, 0.8, 1.6, 10.0]
const COL_SMOKE := Color(0.22, 0.2, 0.19)
const COL_SMOKE_C := Color(0.46, 0.43, 0.41)   # the cotton smoke's tint (the tuft's own shading darkens it: lit top, shaded underside)
var _clock := 0.0
## Enemy units that dropped out of sight (the last-seen ghost, game/last_seen.gd).
var last_seen := LastSeen.new()
const COL_GHOST := Color(0.6, 0.62, 0.66)
var fx_trk_us := 0
var fx_us := 0                         # view cost of the effects (track + draw), microseconds, for benchmarks
var _fx_kind := PackedInt32Array()
var _fx_age := PackedFloat32Array()
var _fx_pos := PackedVector2Array()
var _fx_rad := PackedFloat32Array()    # blast radius in px
var _tr_t0 := PackedInt32Array()       # per slot: t0 of the missile last classified (-1 none)
var _tr_stamp := PackedInt32Array()    # per slot: the walk that saw it
var _tr_live := PackedInt32Array()     # slots of fire / explosive / stone missiles in flight
var _tr_rec := {}                      # slot -> [kind, x, y, radius (sim units)]
var _tr_walk := 0
var _fx_cell := {}                     # landing cell -> view clock of the last effect there
var _tr_tick := -1
## The sim tick of each unit's last gun shot by men (view only; the soldier
## layer reads it: the muzzle flash frame shows only for a fresh shot).
var shot_t := PackedInt32Array()
## The muzzle flashes of men's gun shots (view only): one per shot, at that man's muzzle (the missile's start), so only a man who
## fired this tick flashes (2026-11-06; the unit-wide atlas flash frame is gone). Musket / arquebus: FLASH_MUSKET_S; a rider's
## pistol (cavalry class): FLASH_PISTOL_S. Aged by real time, so a paused sim's flash dies away as well.
const FLASH_MUSKET_S := 0.12
const FLASH_PISTOL_S := 0.06
var _mf_pos := PackedVector2Array()
var _mf_dir := PackedVector2Array()
var _mf_age := PackedFloat32Array()
var _mf_life := PackedFloat32Array()
var _mf_sz := PackedFloat32Array()
var flashes_made := 0                  # (tests)
var flashes_live: int:                 # flashes still showing (tests)
	get: return _mf_age.size()
var _bk_seen := -1                     # blocked shots seen so far (sim.bk_n; -1: not looked yet)
var _ev_seen := -1                     # destruction events seen so far (sim.ev_n; -1: not looked yet)
# Gun smoke (docs/DESIGN.md "Firearms"; view only, no sim state): each gun
# missile seen leaving puts a white puff (one per SMOKE_CELL_M cell per
# volley) in front of the man or engine that fired it, with a muzzle flash
# for its first frames; the puffs grow, drift with a fixed battle wind and
# fade over GunSmoke.LIFE s. Graphics Low: bigger cells, fewer puffs, one
# circle each. (Smoke that blocks aim in the sim is a later item.)
const SMOKE_WIND := Vector2(0.8, -0.35)   # m/s
const SMOKE_CELL_M := [2.5, 6.0]          # high, low
const SMOKE_CAP := [280, 70]
const GunSmoke := preload("res://game/gun_smoke.gd")
const TrayLayer := preload("res://game/tray_layer.gd")
var _gs := GunSmoke.new()                # the banks, flashes and haze (game/gun_smoke.gd)
var _sm_cell := {}                        # cell -> view clock of its last puff
var _sm_low := false
var _sm_low_t := -10.0
var smoke_puffs: int:                     # puffs made (tests, benchmarks)
	get: return _gs.puffs_made
var _props: Node2D                     # draws the wagon sprites (behind the overlay's lines)
var _tex_warm := false
var _up_on := false                    # the oblique view: items now drawn upright (see _up)
## The oblique view: a unit marker floats this much higher (world px a metre: over the upright figures).
const FIG_LIFT_M := 1.7
var _props_tex: Texture2D
var _q_moved := {}                     # wagon -> [x, y, tick it last moved]


func _process(delta: float) -> void:
	if sim == null:
		return
	_clock += delta
	if not _tex_warm:
		_tex_warm = true
		GunSmoke.texture()   # (the cotton atlas baked now, not in the first frame that draws a puff)
	if (sim.ch_on != 0 or sim.vis_on != 0) and player_side >= 0:
		var now := Time.get_ticks_msec()
		last_seen.update(sim, player_side, now, not Quality.is_low())
		if last_seen.animating(now):
			queue_redraw()
	if sim.sg_on != 0:
		if _props == null:
			_props = Node2D.new()
			_props.show_behind_parent = true
			_props.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
			_props.draw.connect(_draw_props)
			add_child(_props)
			BoardView.lift_node(_props)
			if ResourceLoader.exists(ATLAS_SHADE_PATH) and SpriteAtlas.PROPS.has("wagon"):
				_props_tex = load(ATLAS_SHADE_PATH) as Texture2D
		_props.queue_redraw()
	if _clock - _sm_low_t > 2.0:
		_sm_low_t = _clock
		_sm_low = Quality.is_low()
		_gs.haze_on = not _sm_low
		_gs.cap = int(SMOKE_CAP[1 if _sm_low else 0])
	_gs.tick(delta, SMOKE_WIND * px_per_m)
	var i := 0
	while i < _fx_kind.size():
		_fx_age[i] += delta
		if _fx_age[i] >= FX_LIFE[_fx_kind[i]]:
			_fx_kind.remove_at(i)
			_fx_age.remove_at(i)
			_fx_pos.remove_at(i)
			_fx_rad.remove_at(i)
		else:
			i += 1
	var mf := 0
	while mf < _mf_age.size():
		_mf_age[mf] += delta
		if _mf_age[mf] >= _mf_life[mf]:
			_mf_pos.remove_at(mf)
			_mf_dir.remove_at(mf)
			_mf_age.remove_at(mf)
			_mf_life.remove_at(mf)
			_mf_sz.remove_at(mf)
		else:
			mf += 1
	if sim.tick != _tr_tick and sim.pr_bucket.size() > 0:
		var t0 := Time.get_ticks_usec()
		_track_missiles()
		if sim.ft_on != 0:
			_blocked_shots()
		fx_trk_us += Time.get_ticks_usec() - t0
	if sim.tick != _tr_tick and sim.city_on != 0:
		_destr_events()
	_tr_tick = sim.tick


## Walk the landing buckets (only the missiles in flight), note the fire,
## explosive and stone ones, and turn those no longer in flight into effects.
func _track_missiles() -> void:
	var cap: int = sim.pr_t1.size()
	if _tr_t0.size() != cap:
		_tr_t0.resize(cap)
		_tr_t0.fill(-1)
		_tr_stamp.resize(cap)
		_tr_stamp.fill(0)
		_tr_live.clear()
		_tr_rec.clear()
	_tr_walk += 1
	var buckets: PackedInt32Array = sim.pr_bucket
	var pr_next: PackedInt32Array = sim.pr_next
	var pr_t0: PackedInt32Array = sim.pr_t0
	for b in buckets.size():
		var p := buckets[b]
		while p >= 0:
			_tr_stamp[p] = _tr_walk
			if _tr_t0[p] != pr_t0[p]:
				_tr_note(p)
			p = pr_next[p]
	var k := 0
	while k < _tr_live.size():
		var p := _tr_live[k]
		if _tr_stamp[p] == _tr_walk and _tr_t0[p] == _tr_rec[p][4]:
			k += 1
			continue
		var rec: Array = _tr_rec[p]
		_tr_rec.erase(p)
		_tr_live.remove_at(k)
		_fx_spawn(rec[0], to_px(rec[1], rec[2]), rec[3] * px_per_m / M)


func _tr_note(p: int) -> void:
	var ak: int = sim.pr_ak[p]
	var ty: int = sim.pr_ty[p]
	if sim.t_m_gun[ty] != 0 and sim.tick - sim.pr_t0[p] <= 3:
		# A gun shot: an engine's big puff, or a man's bank puff with his flash
		# frame (every shot, in line or not).
		_smoke_spawn(p, ty)
		if sim.t_cls[ty] != UT.CLS_ART:
			var u: int = sim.pr_unit[p]
			if shot_t.size() != sim.n_units:
				shot_t.resize(sim.n_units)
				shot_t.fill(-1000)
			if u >= 0 and u < shot_t.size():
				shot_t[u] = maxi(shot_t[u], sim.pr_t0[p])
			_flash_add(p, ty)
	var kind := 0
	var rad := 0
	if ak >= 0 and UT.ammo_stat(ak, "fire") > 0:
		kind = FX_FIRE
	elif ak >= 0 and UT.ammo_stat(ak, "blast") > 0:
		kind = FX_BLAST
		rad = UT.stat(ty, "m_blast") + UT.ammo_stat(ak, "blast")
	elif UT.stat(ty, "m_kind") == 2:
		kind = FX_DUST
	if _tr_rec.has(p):
		# the slot was reused within one walk: the old missile landed
		var old: Array = _tr_rec[p]
		_tr_rec.erase(p)
		_tr_live.remove_at(_tr_live.find(p))
		_fx_spawn(old[0], to_px(old[1], old[2]), old[3] * px_per_m / M)
	_tr_t0[p] = sim.pr_t0[p]
	if kind != 0:
		_tr_rec[p] = [kind, sim.pr_x[p], sim.pr_y[p], rad, sim.pr_t0[p]]
		_tr_live.append(p)


## Flat shots stopped by a wall, house or rock since the last look (the
## sim's ring of where they stopped, BattleSim.bk_x / bk_y): a puff of dust
## there (pathing phase C0).
func _blocked_shots() -> void:
	var n: int = sim.bk_n
	if _bk_seen < 0 or n < _bk_seen:
		_bk_seen = n  # (a fresh view or a restored sim: nothing to replay)
		return
	for k in range(maxi(_bk_seen, n - BattleSim.BK_N), n):
		var r := k % BattleSim.BK_N
		_fx_spawn(FX_CHIP, to_px(sim.bk_x[r], sim.bk_y[r]), 0.0)
	_bk_seen = n


## Walls breached and buildings fallen since the last look (the sim's events ring, BattleSim.ev_*):
## dust rings along the piece (FX_BLAST) and a haze over it fading for 10 s (FX_RUIN).
func _destr_events() -> void:
	var n: int = sim.ev_n
	if _ev_seen < 0 or n < _ev_seen:
		_ev_seen = n  # (a fresh view or a restored sim: nothing to replay)
		return
	for k in range(maxi(_ev_seen, n - BattleSim.EV_N), n):
		var r := k % BattleSim.EV_N
		var a: int = sim.ev_a[r]
		var pts: Array[Vector2] = []
		var rad := 0.0
		if sim.ev_k[r] == BattleSim.EV_BREACH and a < sim.ws_x0.size():
			var p0 := to_px(sim.ws_x0[a], sim.ws_y0[a])
			var p1 := to_px(sim.ws_x1[a], sim.ws_y1[a])
			for q in 4:
				pts.append(p0.lerp(p1, (q + 0.5) / 4.0))
			rad = p0.distance_to(p1) / 4.0
		elif sim.ev_k[r] == BattleSim.EV_COLLAPSE:
			var blds: Array = (sim.map_info.get("city", {}) as Dictionary).get("buildings", [])
			if a < blds.size():
				var b: Array = blds[a]
				pts.append(Vector2(float(int(b[0]) + int(b[2])), float(int(b[1]) + int(b[3]))) * 0.5 * px_per_m)
				rad = maxf(float(int(b[2]) - int(b[0])), float(int(b[3]) - int(b[1]))) * 0.5 * px_per_m
		elif sim.ev_k[r] == BattleSim.EV_FIRE:
			# (A building caught fire: a burst of sparks; the flames themselves are _draw_bld_fires.)
			var bf: Array = (sim.map_info.get("city", {}) as Dictionary).get("buildings", [])
			if a < bf.size():
				var b2: Array = bf[a]
				_fx_spawn(FX_FIRE, Vector2(float(int(b2[0]) + int(b2[2])), float(int(b2[1]) + int(b2[3]))) * 0.5 * px_per_m, px_per_m * 2.0)
			continue
		for pt in pts:
			_fx_spawn(FX_BLAST, pt, maxf(rad, px_per_m * 3.0))
			_fx_spawn(FX_RUIN, pt, maxf(rad, px_per_m * 3.0))
	_ev_seen = n


## Gun missile p (of type ty) has just left: a big puff (an engine) or a bank puff (a man).
## The flash of one man's shot (missile p), at his muzzle: a half metre ahead of where the ball started, along its flight.
func _flash_add(p: int, ty: int) -> void:
	if _mf_age.size() >= 400:
		return
	var s := to_px(sim.pr_sx[p], sim.pr_sy[p])
	var d := to_px(sim.pr_x[p], sim.pr_y[p]) - s
	d = d.normalized() if d.length_squared() > 0.0 else Vector2.UP
	var pistol: bool = UT.stat(ty, "cls") == UT.CLS_CAV
	_mf_pos.append(s + d * px_per_m * 0.5)
	_mf_dir.append(d)
	_mf_age.append(0.0)
	_mf_life.append(FLASH_PISTOL_S if pistol else FLASH_MUSKET_S)
	_mf_sz.append(px_per_m * (0.22 if pistol else 0.34))
	flashes_made += 1


func _draw_flashes() -> void:
	var vr := _view_rect().grow(px_per_m * 4.0)
	var up := BoardView.oblique
	for k in _mf_age.size():
		if vr.has_point(_mf_pos[k]):
			GunSmoke.flash(self, _mf_pos[k], _mf_dir[k], _mf_sz[k], 1.0 - _mf_age[k] / _mf_life[k], up, px_per_m * 1.1)
	if up:
		draw_set_transform_matrix(Transform2D.IDENTITY)


func _smoke_spawn(p: int, ty: int) -> void:
	var s := to_px(sim.pr_sx[p], sim.pr_sy[p])
	var d := to_px(sim.pr_x[p], sim.pr_y[p]) - s
	d = d.normalized() if d.length_squared() > 0.0 else Vector2.UP
	_smoke_at(s, d, UT.stat(ty, "cls") == UT.CLS_ART)


## A bank puff in front of a muzzle at s (direction d), unless this volley
## already put one in that cell; a gun engine's shot adds a ring of smoke and
## a dust kick.
func _smoke_at(s: Vector2, d: Vector2, big: bool) -> void:
	var pm := px_per_m
	var at := s + d * pm * (2.0 if big else 1.2)
	var lo := 1 if _sm_low else 0
	var cell := Vector2i((at / (pm * float(SMOKE_CELL_M[lo]))).floor())
	if not big and _sm_cell.get(cell, -10.0) > _clock - 1.0:
		return
	_sm_cell[cell] = _clock
	if _sm_cell.size() > 1024:
		_sm_cell.clear()
	if big:
		_gs.add_big(at, d, pm * 3.6, pm * 8.0, not _sm_low, 0 if _sm_low else 6)
	else:
		_gs.add(at, d, pm * 2.1, pm * (3.0 if _sm_low else 4.0), 0, false)
	_gs.feed_haze(at, pm * 14.0, 0.25 if big else 0.04)


func _draw_smoke() -> void:
	_gs.draw(self, SMOKE_WIND * px_per_m, _view_rect().grow(px_per_m * 20.0), px_per_m * 12.0, preload("res://game/battle_look.gd").is_diorama(), BoardView.oblique)


func _fx_spawn(kind: int, at: Vector2, rad: float) -> void:
	if kind != FX_BLAST:
		# A volley lands as one: no second spark / puff in the same 2 m cell for 0.4 s.
		var cell := Vector2i(at / (px_per_m * 2.0)) * 4 + Vector2i(kind, 0)
		if _fx_cell.get(cell, -10.0) > _clock - 0.4:
			return
		_fx_cell[cell] = _clock
		if _fx_cell.size() > 512:
			_fx_cell.clear()
	if _fx_kind.size() >= FX_CAP:
		# Drop the oldest, but keep blasts over sparks and dust.
		var drop := 0
		while drop < _fx_kind.size() - 1 and _fx_kind[drop] == FX_BLAST and kind != FX_BLAST:
			drop += 1
		_fx_kind.remove_at(drop)
		_fx_age.remove_at(drop)
		_fx_pos.remove_at(drop)
		_fx_rad.remove_at(drop)
	_fx_kind.append(kind)
	_fx_age.append(0.0)
	_fx_pos.append(at)
	_fx_rad.append(rad)


## The visible part of the world (px), with a margin, for culling effects.
func _view_rect() -> Rect2:
	var r := BoardView.world_rect(get_canvas_transform().affine_inverse() * get_viewport_rect())
	return r.grow(80.0)


## A column of drifting smoke over p: n puffs through their life, rising
## `rise` px and spreading to `rad` px; a is the strongest alpha.
func _smoke_column(p: Vector2, seed_k: int, n: int, rise: float, rad: float, a: float, phase: float) -> void:
	for k in n:
		var s := fposmod(phase + float(k) / n, 1.0)
		var sway := sin(float(seed_k) * 1.3 + s * 5.0 + k) * rad * 0.5
		var c := p + Vector2(sway + rise * 0.25 * s, -rise * s)
		GunSmoke.tuft(self, c, rad * (0.35 + 0.65 * s) * 1.5, Color(COL_SMOKE_C, a * sin(PI * s) * (1.0 - 0.5 * s) * 1.5), seed_k + k)


func _draw_fx(lw: float) -> void:
	var vr := _view_rect()
	var pm := px_per_m
	for i in _fx_kind.size():
		var p := _fx_pos[i]
		if not vr.has_point(p):
			continue
		var a := _fx_age[i]
		var sd := int(absf(p.x) * 7.0 + absf(p.y) * 13.0)
		_up(p)   # (the oblique view: the effect stands up at its ground point, as a billboard; the ground rings lie flat)
		match _fx_kind[i]:
			FX_FIRE:
				if a < 0.38:
					var f := a / 0.4
					var h := pm * 1.3 * (1.0 - f)
					draw_colored_polygon(PackedVector2Array([p + Vector2(-h * 0.4, 0), p + Vector2(0, -h * 1.3),
						p + Vector2(h * 0.4, 0)]), Color(1.0, 0.5, 0.12, 0.9 * (1.0 - f)))
					for k in 4:
						var ang := float(sd % 7) + k * 1.6
						var d := pm * (0.3 + 1.3 * f) * (0.7 + 0.1 * (k % 3))
						draw_circle(p + Vector2(cos(ang), sin(ang) * 0.6 - 0.6 * f) * d, maxf(pm * 0.14, 1.2 / zoom),
							Color(1.0, 0.85 - 0.4 * f, 0.25, 1.0 - f))
				var s := a / 2.0
				for k in 2:
					var c := p + Vector2((k - 0.5) * pm * 0.7 * s + pm * 1.2 * s, -pm * (0.6 + 3.0 * s) - k * pm * 0.5 * s)
					GunSmoke.tuft(self, c, pm * (0.5 + 1.1 * s) * 1.5, Color(COL_SMOKE_C, 0.5 * (1.0 - s) * (0.8 + 0.1 * k)), sd + k)
			FX_BLAST:
				var rr := maxf(_fx_rad[i], pm * 1.5)
				if a < 0.15:
					draw_circle(p, rr * 0.9, Color(1.0, 0.95, 0.7, 0.9 * (1.0 - a / 0.15)))
				if a < 0.5:
					var f := a / 0.5
					GunSmoke.tuft(self, p + Vector2(0, -rr * 0.3 * f if BoardView.oblique else 0.0), rr * (0.3 + 0.8 * f) * 1.5, Color(0.55, 0.47, 0.38, 0.6 * (1.0 - f)), sd)
					_flat()
					draw_arc(p, rr * (0.35 + 0.9 * f), 0.0, TAU, 28, Color(0.8, 0.7, 0.55, 0.85 * (1.0 - f)), lw * 2.0)
					_up(p)
				var s := a / 3.0
				for k in 4:
					var ang := float(sd % 5) + k * 1.57
					var c := p + Vector2(cos(ang) * rr * 0.4 * (0.4 + s) + pm * s, sin(ang) * rr * 0.3 - rr * (0.3 + 1.2 * s))
					GunSmoke.tuft(self, c, rr * (0.45 + 0.5 * s) * 1.5, Color(COL_SMOKE_C, 0.55 * clampf(1.0 - s, 0.0, 1.0) * minf(1.0, a * 5.0)), sd + k)
			FX_RUIN:
				# A pale dust haze over the rubble, settling and fading over 10 s.
				var f := a / 10.0
				var rr2 := _fx_rad[i]
				for k in 3:
					var ang2 := float((sd + k * 5) % 9) * 0.7
					var c2 := p + Vector2(cos(ang2) * rr2 * 0.35 + pm * 1.5 * f * k, sin(ang2) * rr2 * 0.25 - rr2 * 0.3 * f)
					GunSmoke.tuft(self, c2, rr2 * (0.7 + 0.5 * f) * 1.5, Color(0.8, 0.73, 0.62, 0.5 * (1.0 - f) * minf(1.0, a * 3.0)), sd + k)
			FX_DUST:
				var f := a / 0.8
				GunSmoke.tuft(self, p + Vector2(0, -pm * (0.35 + 0.9 * f) * 0.5 if BoardView.oblique else 0.0), pm * (0.35 + 0.9 * f) * 1.5, Color(0.7, 0.58, 0.42, 0.5 * (1.0 - f)), sd)
			FX_CHIP:
				# (Seen at any zoom: at least a few pixels across.)
				var f := a / 1.6
				var r0 := maxf(pm, 3.0 / zoom)
				if a < 0.12:
					draw_circle(p, r0 * 0.9, Color(1.0, 0.95, 0.8, 0.85 * (1.0 - a / 0.12)))
				for k in 3:
					var ang := float((sd + k * 7) % 11) * 0.57
					var c := p + Vector2(cos(ang), sin(ang)) * r0 * (0.4 + 2.2 * minf(a * 3.0, 1.0))
					if a < 0.5:
						draw_circle(c, r0 * 0.18, Color(0.35, 0.3, 0.24, 0.9 * (1.0 - a / 0.5)))
				GunSmoke.tuft(self, p + Vector2(0, -r0 * 0.6 * f), r0 * (0.6 + 1.2 * f) * 1.5, Color(0.85, 0.76, 0.6, 0.7 * (1.0 - f)), sd)
				GunSmoke.tuft(self, p + Vector2(r0 * 0.5 * f, -r0 * 1.1 * f), r0 * (0.4 + 0.9 * f) * 1.5, Color(0.72, 0.64, 0.5, 0.55 * (1.0 - f)), sd + 1)
	_flat()


## Burning units: a few of the men (every 7th, at most 12) carry a flame and
## a thread of smoke while u_burn lasts.
func _draw_burning_units(vr: Rect2) -> void:
	var t := _clock * 6.0
	var pm := px_per_m
	for u in sim.n_units:
		if sim.u_burn[u] <= 0 or sim.u_alive[u] <= 0:
			continue
		var alive: int = sim.u_alive[u]
		var base: int = sim.u_slot_base[u]
		var step := maxi(7, alive / 12)
		var k: int = (u * 3) % step
		var n := 0
		while k < alive and n < 12:
			var i: int = sim.slot_soldier[base + k]
			var p := to_px(sim.pos_x[i], sim.pos_y[i])
			if vr.has_point(p):
				_up(p)
				var f := 0.75 + 0.25 * sin(t + i * 1.9)
				var h := maxf(pm * 1.3, 8.0 / zoom) * f
				var w := h * 0.4
				p += Vector2(0, -pm * 0.8)
				draw_colored_polygon(PackedVector2Array([p + Vector2(-w, 0), p + Vector2(0, -h), p + Vector2(w, 0)]),
					Color(1.0, 0.45, 0.1, 0.85))
				draw_colored_polygon(PackedVector2Array([p + Vector2(-w * 0.5, 0), p + Vector2(0, -h * 0.6),
					p + Vector2(w * 0.5, 0)]), Color(1.0, 0.85, 0.3, 0.9))
				if n % 2 == 0:
					_smoke_column(p - Vector2(0, h * 0.5), i, 2, pm * 3.0, pm * 0.9, 0.32, _clock * 0.5 + i * 0.17)
				_flat()
			k += step
			n += 1


## Light wall stretch sg for a moment (what a tap on a wall chose).
func flash_stretch(sg: int) -> void:
	_stretch_flash = sg
	_stretch_until = Time.get_ticks_msec() + STRETCH_FLASH_MS
	queue_redraw()


## Show `text` at world point `at` for a couple of seconds.
func flash(text: String, at: Vector2) -> void:
	_flash_text = text
	_flash_at = at
	_flash_until = Time.get_ticks_msec() + FLASH_MS


func _v(u: int, key: String) -> int:
	if orders != null:
		return orders.value(u, key)
	return (sim.get("u_" + key) as PackedInt32Array)[u]


## Files unit u's formation is drawn with: its carry pattern's while it
## carries a piece (or, in the deployment, has one assigned pending), else
## its predicted ordered files.
func _fv(u: int) -> int:
	var q: int = sim.u_carry[u] if u < sim.u_carry.size() else -1
	if q < 0 and sim.phase == BattleSim.PHASE_DEPLOY:
		var pk := _v(u, "pick")
		if pk >= 0 and pk < sim.n_eq:
			q = pk
	if q >= 0:
		var cf := BattleSim.carry_files(sim, u, q)
		if cf > 0:
			return cf
	return _v(u, "files")


## Tabletop pass 3 (the oblique view, game/board_view.gd): the overlay's node draws through the lift shader, so the
## ground marks lie on the board; the items after _up(anchor) stand upright at the anchor's board point until _flat().
## Nothing changes in the top view.
func _up(anchor: Vector2) -> void:
	if BoardView.oblique:
		draw_set_transform_matrix(BoardView.up_xf(anchor))
		_up_on = true


## Tabletop pass 3 leftovers (the oblique view): lines, dashes, polylines and arcs lying on the ground go to their board
## points only at their vertices (board_lift.gdshader), so a long one across a hill would cut through it. In the oblique view
## they are drawn in pieces of at most SEG_M metres so they follow the lift grid; the top view draws them as before.
const SEG_M := 8.0
const BrassRule := preload("res://game/brass_rule.gd")


func _dl(a: Vector2, b: Vector2, col: Color, w := -1.0, aa := false) -> void:
	if not BoardView.oblique or _up_on:
		draw_line(a, b, col, w, aa)
		return
	var n := ceili(a.distance_to(b) / (SEG_M * px_per_m))
	if n <= 1:
		draw_line(a, b, col, w, aa)
		return
	var pts := PackedVector2Array()
	for k in n + 1:
		pts.append(a.lerp(b, float(k) / n))
	draw_polyline(pts, col, w, aa)


func _dp(pts: PackedVector2Array, col: Color, w := -1.0, aa := false) -> void:
	if not BoardView.oblique or _up_on:
		draw_polyline(pts, col, w, aa)
		return
	var seg := SEG_M * px_per_m
	var out := PackedVector2Array()
	for k in pts.size():
		if k > 0:
			var n := ceili(pts[k - 1].distance_to(pts[k]) / seg)
			for j in range(1, n):
				out.append(pts[k - 1].lerp(pts[k], float(j) / n))
		out.append(pts[k])
	draw_polyline(out, col, w, aa)


func _dd(a: Vector2, b: Vector2, col: Color, w := -1.0, dash := 2.0, aligned := true) -> void:
	var dist := a.distance_to(b)
	var seg := SEG_M * px_per_m
	if not BoardView.oblique or _up_on or dist <= seg:
		draw_dashed_line(a, b, col, w, dash, aligned)
		return
	# (Pieces of whole dash periods, so the pattern carries on across the joins.)
	var period := maxf(dash * 2.0, 1.0)
	var step := maxf(floorf(seg / period), 1.0) * period
	var d := 0.0
	var dir := (b - a) / dist
	while d < dist:
		var e := minf(d + step, dist)
		draw_dashed_line(a + dir * d, a + dir * e, col, w, dash, false)
		d = e


func _da(c: Vector2, r: float, a0: float, a1: float, pts: int, col: Color, w := -1.0, aa := false) -> void:
	if BoardView.oblique and not _up_on:
		pts = maxi(pts, ceili(r * absf(a1 - a0) / (SEG_M * px_per_m)))
	draw_arc(c, r, a0, a1, pts, col, w, aa)


## A small label of the brass ruler (its numbers): upright in the oblique view, with a dark shadow so it reads on any ground.
func _rule_label(pos: Vector2, text: String, fs: float, col: Color) -> void:
	var f := int(roundf(fs))
	var tw := ThemeDB.fallback_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, f).x
	var at := pos + Vector2(-tw * 0.5, f * 0.35)
	var o := 0.7 / zoom
	_dstr(at + Vector2(o, o), text, HORIZONTAL_ALIGNMENT_LEFT, -1, f, Color(0.12, 0.07, 0.02, col.a * 0.85))
	_dstr(at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, f, col)


func _flat() -> void:
	if _up_on:
		draw_set_transform_matrix(Transform2D.IDENTITY)
		_up_on = false


## A label: upright where it is in the oblique view (or in the current upright group), else as before.
func _dstr(pos: Vector2, text: String, align: HorizontalAlignment, width: float, fs: int, col: Color) -> void:
	if not BoardView.oblique or _up_on:
		draw_string(ThemeDB.fallback_font, pos, text, align, width, fs, col)
		return
	draw_set_transform_matrix(BoardView.up_xf(pos))
	draw_string(ThemeDB.fallback_font, pos, text, align, width, fs, col)
	draw_set_transform_matrix(Transform2D.IDENTITY)


## How far above a unit's centre its marker floats (world px; r the marker radius): over the figures in the oblique view.
static func marker_dy(r: float) -> float:
	return r * 2.2 + (FIG_LIFT_M * BoardView.px_per_m if BoardView.oblique else 0.0)


func to_px(x: int, y: int) -> Vector2:
	return Vector2(x, y) * (px_per_m / M)


func _font_size(base: float) -> int:
	return int(maxf(10.0, base / zoom))


## Deployment phase: this player's zone (blue, filled) and the enemy's
## (red outline). A settlement defenders' zone is the whole town: inside
## the walls and on the walkways (DZ_INSIDE, its box outlined) and, in a
## West town with a harbour fort (2026-11-02), the town's box as well; the
## first of them is labelled.
func _draw_deploy_zones(lw: float) -> void:
	var z: PackedInt32Array = sim.dep_z
	var k := 0
	var labelled := false
	var kinds := 0  # (bit per kind of the defenders' zones: both, a West town with its fort)
	if sim.city_on != 0:
		for k2 in range(0, z.size() - 5, 6):
			if z[k2] == sim.city_def:
				kinds |= 1 << z[k2 + 1]
	var fort := kinds == (1 << BattleSim.DZ_RECT) | (1 << BattleSim.DZ_INSIDE)
	var town_text := "Deploy anywhere in the town, on its walls or in the fort" if fort \
		else "Deploy anywhere in the town or on its walls"
	while k + 5 < z.size():
		var mine := z[k] == player_side
		var r := Rect2(Vector2(z[k + 2], z[k + 3]) / 1024.0 * px_per_m,
			Vector2(z[k + 4] - z[k + 2], z[k + 5] - z[k + 3]) / 1024.0 * px_per_m)
		var col := Color(0.35, 0.65, 1.0) if mine else Color(1.0, 0.4, 0.3)
		var town_z: bool = sim.city_on != 0 and z[k] == sim.city_def
		if mine and town_z and not labelled and (z[k + 1] == BattleSim.DZ_RECT or not fort):
			labelled = true
			var fs := _font_size(14.0)
			_dstr(r.position + Vector2(fs * 0.4, fs * 1.4),
				town_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(col, 0.95))
		if z[k + 1] == BattleSim.DZ_INSIDE:
			draw_rect(r, Color(col, 0.07 if mine else 0.0))
			draw_rect(r, Color(col, 0.75 if mine else 0.45), false, lw * (1.5 if mine else 1.0))
		elif mine:
			# (The brass ruler: the line of my deployment zone, ticks from each corner.)
			draw_rect(r, Color(col, 0.10))
			var c0 := r.position
			var c1 := Vector2(r.end.x, r.position.y)
			var c2 := r.end
			var c3 := Vector2(r.position.x, r.end.y)
			BrassRule.band(self, PackedVector2Array([c0, c1, c2, c3, c0]), px_per_m, zoom)
			var cen := r.get_center()
			var lab := Callable(self, "_rule_label")
			BrassRule.ticks(self, PackedVector2Array([c0, c1]), cen, px_per_m, zoom, lab)
			BrassRule.ticks(self, PackedVector2Array([c1, c2]), cen, px_per_m, zoom, lab)
			BrassRule.ticks(self, PackedVector2Array([c2, c3]), cen, px_per_m, zoom, lab)
			BrassRule.ticks(self, PackedVector2Array([c3, c0]), cen, px_per_m, zoom, lab)
		else:
			draw_rect(r, Color(col, 0.05))
			draw_rect(r, Color(col, 0.5), false, lw)
		k += 6


func _draw() -> void:
	if sim == null:
		return
	_up_on = false
	var lw := maxf(1.5, 2.0 / zoom)
	var r := maxf(MARKER_MIN_R, MARKER_SCREEN_R / zoom)
	if _icon.size() != sim.n_units:
		_icon.resize(sim.n_units)
		for u in sim.n_units:
			_icon[u] = Icons.icon_of(sim.u_otype[u])
	if sim.phase == BattleSim.PHASE_DEPLOY:
		_draw_deploy_zones(lw)
	if sim.city_on != 0:
		_draw_city_marks(lw)
		if sim.occ_on != 0 or sim.fort_on != 0:
			_draw_held(lw)
		if occ_mode or occ_focus >= 0:
			_draw_occupy(lw)
	if sim.sg_on != 0:
		_draw_siege_gear(lw)
	if sim.fire_on != 0:
		_draw_fires(lw)
	var fx0 := Time.get_ticks_usec()
	if sim.stat_unit_burn > 0:
		_draw_burning_units(_view_rect())
	if not _fx_kind.is_empty():
		_draw_fx(lw)
	if not _gs.age.is_empty() or not _gs.hz_amt.is_empty():
		_draw_smoke()
	if not _mf_age.is_empty():
		_draw_flashes()
	fx_us += Time.get_ticks_usec() - fx0
	if show_all_orders:
		_draw_all_orders()
	if sim.n_eng > 0:
		_draw_impacts(lw)
		_draw_free_engines(r, lw)
	if sim.sg_on != 0:
		_draw_free_towers(r, lw)
	if trays != null:
		_draw_standards(r)
	_draw_markers(r, lw)
	if not last_seen.recs.is_empty():
		_draw_last_seen(r, lw)
	for tu in target_lit:
		if tu < sim.n_units and sim.u_state[tu] < BattleSim.U_DESTROYED:
			var tp := to_px(sim.u_cx[tu], sim.u_cy[tu])
			draw_arc(tp, r * 1.45, 0.0, TAU, 28, Color(0, 0, 0, 0.6), lw * 2.2)
			draw_arc(tp, r * 1.45, 0.0, TAU, 28, Color(1.0, 0.82, 0.25, 0.95), lw * 1.2)
	var primary := selected_units[0] if not selected_units.is_empty() else -1
	for u in selected_units:
		if u >= 0 and u < sim.n_units and sim.u_state[u] < BattleSim.U_DESTROYED:
			_draw_selected(u, lw, r, u == primary)
	if hover_w.x >= 0.0 and not preview_on:
		_draw_wall_hover(hover_w, lw)
		if not occ_mode and sim.city_on != 0 and orders != null and not selected_units.is_empty():
			_draw_hover_route(hover_w, lw)
	if _stretch_flash >= 0 and Time.get_ticks_msec() < _stretch_until and _stretch_flash < sim.ws_x0.size():
		_draw_stretch(_stretch_flash, lw, 0.9)
	if preview_on:
		_draw_preview(lw)
	if place_on:
		_draw_place(lw)
	if sim.phase == BattleSim.PHASE_DEPLOY and sim.fw_on != 0:
		_draw_works_pending(lw)
	for g in ghosts:
		var u: int = g["unit"]
		_draw_footprint(u, g["front"], g["face"], g["files"], sim.u_alive[u],
			Color(0.6, 1.0, 1.0, 0.95), Color(0.6, 1.0, 1.0, 0.16), lw)
	if ghost_hint != "" and not ghosts.is_empty():
		var at: Vector2 = ghosts[0]["front"]
		var fs := _font_size(15.0)
		_dstr(at + Vector2(0, -fs * 1.2), ghost_hint, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.7, 1, 1))
	if box_on:
		var rect := Rect2(box_a, box_b - box_a).abs()
		draw_rect(rect, Color(1, 1, 1, 0.12))
		draw_rect(rect, Color(1, 1, 1, 0.8), false, lw)
	if _flash_text != "" and Time.get_ticks_msec() < _flash_until:
		var ffs := _font_size(14.0)
		var tw := ThemeDB.fallback_font.get_string_size(_flash_text, HORIZONTAL_ALIGNMENT_LEFT, -1, ffs).x
		var at := _flash_at + Vector2(-tw * 0.5, -ffs * 1.6)
		_up(_flash_at)
		draw_rect(Rect2(at + Vector2(-ffs * 0.4, -ffs * 1.05), Vector2(tw + ffs * 0.8, ffs * 1.45)), Color(0, 0, 0, 0.6))
		_dstr(at, _flash_text, HORIZONTAL_ALIGNMENT_LEFT, -1, ffs, Color(1, 0.95, 0.8))
		_flat()


## Settlement: hit points over each closed gate (a word over an open or a
## broken one), and the capture ring with "Plaza held N / 60 s" ("Citadel
## held" where the capture point is a citadel's court) while the attackers
## hold it.
func _draw_city_marks(lw: float) -> void:
	var lay: Dictionary = sim.map_info.get("city", {})
	if lay.is_empty():
		return
	var k := px_per_m
	for g in sim.n_gates:
		var gd: Dictionary = lay["gates"][g]
		var ang: float = int(gd["dir"]) * TAU / 1024.0
		var n := Vector2(cos(ang), sin(ang))
		var c := Vector2(gd["x"], gd["y"]) * k + n * (float(lay["t"]) * 0.5 + 3.0) * k
		var st: int = sim.g_state[g]
		var bw := maxf(10.0 * k, 46.0 / zoom)
		var bh := maxf(1.0 * k, 6.0 / zoom)
		if st == BattleSim.GATE_CLOSED:
			var f := float(sim.g_hp[g]) / maxf(float(sim.g_hp0[g]), 1.0)
			draw_rect(Rect2(c - Vector2(bw * 0.5, bh * 0.5), Vector2(bw, bh)), Color(0, 0, 0, 0.65))
			var col := Color(0.95, 0.75, 0.3) if f > 0.35 else Color(1.0, 0.35, 0.25)
			draw_rect(Rect2(c - Vector2(bw * 0.5, bh * 0.5), Vector2(bw * f, bh)), col)
		elif zoom > 0.35:
			var txt := "BROKEN" if st == BattleSim.GATE_BROKEN else "OPEN"
			_dstr(c + Vector2(-bw * 0.3, bh), txt, HORIZONTAL_ALIGNMENT_LEFT, -1,
				_font_size(12.0), Color(1, 0.85, 0.5) if st == BattleSim.GATE_BROKEN else Color(0.75, 1, 0.75))
	if sim.cap_t > 0:
		var pl: Array = lay["plaza"]
		var pc := Vector2(pl[0], pl[1]) * k
		var r := float(pl[3]) * k
		var frac := clampf(float(sim.cap_t) / BattleSim.CAPTURE_TICKS, 0.0, 1.0)
		var att: int = 1 - sim.city_def
		var col2: Color = COL_SIDE[att]
		draw_arc(pc, r, 0, TAU, 48, Color(0, 0, 0, 0.5), lw * 3.0)
		draw_arc(pc, r, -PI * 0.5, -PI * 0.5 + TAU * frac, 48, col2, lw * 3.0)
		var fs := _font_size(15.0)
		var where := "Citadel" if not (lay.get("cit", {}) as Dictionary).is_empty() and sim.fort_on == 0 else "Plaza"
		var txt2 := "%s held %d / %d s" % [where, sim.cap_t / 10, BattleSim.CAPTURE_TICKS / 10]
		var tw2 := ThemeDB.fallback_font.get_string_size(txt2, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		_dstr(pc + Vector2(-tw2 * 0.5, -r - fs * 0.5), txt2, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col2.lightened(0.3))


## Slice 2c: the buildings held (their outline in the holder's colour, the
## door step marked) and the fort's parade being taken (an arc and its time).
func _draw_held(lw: float) -> void:
	var k := px_per_m
	var lay: Dictionary = sim.map_info.get("city", {})
	var blds: Array = lay.get("buildings", [])
	if sim.occ_on != 0:
		for b in sim.ob_u.size():
			var hu: int = sim.ob_u[b] - 1
			if hu < 0 or hu >= sim.n_units or b >= blds.size():
				continue
			var a: Array = blds[b]
			var col: Color = COL_SIDE[sim.u_side[hu]]
			var pts := PackedVector2Array()
			for q in 4:
				pts.append(Vector2(float(int(a[7 + q * 2])), float(int(a[8 + q * 2]))) * k)
			pts.append(pts[0])
			_dp(pts, Color(0, 0, 0, 0.45), lw * 3.2)
			_dp(pts, Color(col.r, col.g, col.b, 0.9), lw * 1.8)
			var dp := Vector2(sim.ob_dx[b], sim.ob_dy[b]) / 1024.0 * k
			var fa: float = sim.ob_face[b] * TAU / 1024.0
			var e := Vector2(-sin(fa), cos(fa)) * 1.2 * k
			draw_line(dp - e, dp + e, Color(0, 0, 0, 0.6), lw * 3.0)
			draw_line(dp - e, dp + e, col.lightened(0.3), lw * 1.6)
	if sim.fort_on != 0 and sim.fort_t > 0 and sim.fort_taken == 0:
		var fc := Vector2(sim.cit_x, sim.cit_y) / 1024.0 * k
		var fr := float(sim.cit_r) / 1024.0 * k
		var frac := clampf(float(sim.fort_t) / BattleSim.FORT_CAP_TICKS, 0.0, 1.0)
		var col2: Color = COL_SIDE[1 - sim.city_def]
		draw_arc(fc, fr, 0, TAU, 48, Color(0, 0, 0, 0.5), lw * 3.0)
		draw_arc(fc, fr, -PI * 0.5, -PI * 0.5 + TAU * frac, 48, col2, lw * 3.0)
		var fs := _font_size(15.0)
		var txt := "Fort held %d / %d s" % [sim.fort_t / 10, BattleSim.FORT_CAP_TICKS / 10]
		var tw := ThemeDB.fallback_font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		_dstr(fc + Vector2(-tw * 0.5, -fr - fs * 0.5), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col2.lightened(0.3))


## The mouse over the field with units selected in a town: the street route of the primary unit to the
## point (faint, dotted); "No way through" in red where the sim finds none.
func _draw_hover_route(w: Vector2, lw: float) -> void:
	var u := selected_units[0]
	if u < 0 or u >= sim.n_units or sim.u_state[u] != BattleSim.U_READY:
		return
	var c := w / px_per_m * M
	var ho := BattleSim.make_move_order(0, u, int(c.x), int(c.y),
		_v(u, "face"), BattleSim.files_to_width(_v(u, "files"), sim.u_type[u]), 0)
	if append_on:
		ho["append"] = 1
	var rt: Dictionary = orders.move_route_for(u, ho)
	if rt.is_empty():
		return
	var no_way: bool = rt["blocked"]
	var col := COL_NOWAY if no_way else Color(COL_ROUTE, 0.7)
	_draw_route(rt["pts"], col, lw)
	if no_way:
		_dstr(w + Vector2(px_per_m * 1.5, -px_per_m * 2.0), "No way through",
			HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size(13.0), COL_NOWAY)


## The fans of building b at the current range, built once (a few thousand cell reads) and kept.
func occ_fans(b: int) -> Array:
	var key := [b, int(occ_range_m)]
	if not _occ_fans.has(key):
		if _occ_fans.size() > 40:
			_occ_fans.clear()
		var t0 := Time.get_ticks_usec()
		_occ_fans[key] = OccView.fans(sim, b, occ_range_m)
		occ_fan_us = Time.get_ticks_usec() - t0
	return _occ_fans[key]


## The Occupy flow: every building the selection may take outlined in gold with its door step marked, and
## the shown one (occ_focus: the finger's or the mouse's pick, or the one a selected unit holds) with its
## sight fans, its firing places and a tip (kind, places, men held).
func _draw_occupy(lw: float) -> void:
	var k := px_per_m
	if occ_mode:
		for b in occ_lit:
			if b == occ_focus:
				continue
			_draw_occ_outline(b, lw, 0.85, 1.7)
	if occ_focus < 0 or occ_focus >= sim.ob_ok.size():
		return
	var b := occ_focus
	for f in occ_fans(b):
		var pts := PackedVector2Array()
		for p in (f["pts"] as PackedVector2Array):
			pts.append(p * k)
		draw_colored_polygon(pts, Color(COL_OCC, 0.23))
		var edge := pts.slice(1)
		_dp(edge, Color(COL_OCC, 0.7), lw)
		_dl(pts[0], pts[1], Color(COL_OCC, 0.45), lw)
		_dl(pts[0], pts[pts.size() - 1], Color(COL_OCC, 0.45), lw)
	_draw_occ_outline(b, lw, 1.0, 2.6)
	var s0: int = sim.ob_s0[b]
	var pr := maxf(k * 0.28, 1.6)
	for i in sim.ob_sn[b]:
		var pp := Vector2(sim.sp_x[s0 + i], sim.sp_y[s0 + i]) / M * k
		draw_circle(pp, pr * 1.5, Color(0, 0, 0, 0.5))
		draw_circle(pp, pr, COL_OCC.lightened(0.35))
	# The tip, above the building.
	var q := OccView.quad(sim, b)
	if q.size() < 4:
		return
	var top := q[0]
	for v in q:
		if v.y < top.y:
			top = v
	var title := "%s: %d places, holds %d men" % [OccView.kind_name(sim, b), OccView.places(sim, b), OccView.holds(sim, b)]
	var fs := _font_size(14.0)
	var tw := maxf(ThemeDB.fallback_font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x,
		ThemeDB.fallback_font.get_string_size(occ_hint, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)
	var lines := 2 if occ_hint != "" else 1
	var at := Vector2(top.x * k, top.y * k) + Vector2(-tw * 0.5, -fs * 0.8 - (lines - 1) * fs * 1.25)
	var box := Rect2(at + Vector2(-fs * 0.5, -fs * 1.1), Vector2(tw + fs, fs * (0.4 + 1.25 * lines)))
	draw_rect(box, Color(0.12, 0.09, 0.05, 0.9))
	draw_rect(box, Color(COL_OCC, 0.9), false, lw)
	_dstr(at, title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 0.95, 0.8))
	if occ_hint != "":
		_dstr(at + Vector2(0, fs * 1.25), occ_hint, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, COL_OCC)


## Building b's outline in gold over a dark underlay, with the door step marked by a bar and a small chevron.
func _draw_occ_outline(b: int, lw: float, a: float, wk: float) -> void:
	var k := px_per_m
	var q := OccView.quad(sim, b)
	if q.size() < 4:
		return
	var pts := PackedVector2Array()
	for v in q:
		pts.append(v * k)
	pts.append(pts[0])
	draw_colored_polygon(pts.slice(0, 4), Color(COL_OCC, 0.12 * a))
	_dp(pts, Color(0, 0, 0, 0.5 * a), lw * (wk + 1.6))
	_dp(pts, Color(COL_OCC, a), lw * wk)
	var dp := Vector2(sim.ob_dx[b], sim.ob_dy[b]) / M * k
	var fa: float = sim.ob_face[b] * TAU / 1024.0
	var out := Vector2(cos(fa), sin(fa))
	var side := Vector2(-out.y, out.x)
	var e := side * 1.1 * k
	draw_line(dp - e, dp + e, Color(0, 0, 0, 0.6 * a), lw * 3.2)
	draw_line(dp - e, dp + e, COL_OCC.lightened(0.3), lw * 1.8)
	# (A chevron pointing into the door, from the step.)
	var tip := dp - out * 0.2 * k
	var c1 := dp + out * 1.4 * k + side * 0.9 * k
	var c2 := dp + out * 1.4 * k - side * 0.9 * k
	draw_polyline(PackedVector2Array([c1, tip, c2]), Color(0, 0, 0, 0.6 * a), lw * 3.0)
	draw_polyline(PackedVector2Array([c1, tip, c2]), COL_OCC.lightened(0.3), lw * 1.6)


## A hero's or agent's marker (docs/DESIGN.md "Heroes and agents"): his
## disc with a gold rim and his glyph (a crown for the heroes, a dagger for
## the assassin, a scroll for the diplomat); our hidden assassin faded (the
## enemy does not see him); a white flag while the diplomat goes to parley
## (and a ring filling over the 5 s it lasts); a ring filling while the
## assassin works at engines or a gate.
func _draw_char_marker(u: int, c: Vector2, r: float, col: Color, lw: float) -> void:
	var a := 0.45 if sim.u_hidden[u] != 0 else 1.0
	draw_circle(c, r, Color(col, a))
	draw_arc(c, r, 0, TAU, 20, Color(1.0, 0.82, 0.25, a), maxf(r * 0.16, 1.2), true)
	draw_char_glyph(self, sim.u_char[u], c, r * 0.72, Color(1, 1, 1, 0.97 * a), str(UT.TYPES[sim.u_otype[u]].get("glyph", "")))
	var cho: int = sim.u_cho[u]
	if cho == BattleSim.CHO_PARLEY:
		var pole := c + Vector2(r * 1.3, r * 0.9)
		draw_line(pole, pole + Vector2(0, -r * 2.4), Color(0.25, 0.2, 0.15), lw)
		draw_colored_polygon(PackedVector2Array([pole + Vector2(0, -r * 2.4), pole + Vector2(r * 1.4, -r * 2.1),
			pole + Vector2(0, -r * 1.6)]), Color(1, 1, 1, 0.95))
	var k: int = sim.u_chk[u]
	var full := 0
	if cho == BattleSim.CHO_PARLEY and k > 0:
		full = BattleSim.PARLEY_T
	elif cho == BattleSim.CHO_SAB_ENG and k > 0:
		full = BattleSim.SABOTAGE_T
	elif cho == BattleSim.CHO_SAB_GATE and k > 0:
		full = BattleSim.SAB_UNBAR
	if full > 0:
		draw_arc(c, r * 1.35, -PI * 0.5, -PI * 0.5 + TAU * clampf(float(k) / full, 0.0, 1.0), 16,
			Color(1.0, 0.9, 0.5, 0.95), lw * 1.2)


## A character's glyph by kind (UT.CK_*), fitting a circle of radius s: a
## crown (heroes: CK_FOOT .. CK_SIEGE), a dagger (the assassin), a scroll
## (the diplomat). Static: the HUD cards and the unit book may use it too.
static func draw_char_glyph(ci: CanvasItem, kind: int, c: Vector2, s: float, col: Color, glyph: String = "") -> void:
	var w := maxf(s * 0.17, 1.0)
	if glyph != "":
		# The West's four (a row's "glyph": hat, knife, cross, feathers): the UI icon, on the same footing.
		UIIcons.draw_icon(ci, glyph, Rect2(c - Vector2(s, s), Vector2(s, s) * 2.0), col)
	elif kind == UT.CK_ASSASSIN:
		# A dagger point down: blade, guard, grip, pommel.
		ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-0.16, -0.3) * s, c + Vector2(0.16, -0.3) * s,
			c + Vector2(0, 0.95) * s]), col)
		ci.draw_line(c + Vector2(-0.5, -0.32) * s, c + Vector2(0.5, -0.32) * s, col, w * 1.2, true)
		ci.draw_line(c + Vector2(0, -0.32) * s, c + Vector2(0, -0.75) * s, col, w * 1.1, true)
		ci.draw_circle(c + Vector2(0, -0.85) * s, 0.13 * s, col)
	elif kind == UT.CK_DIPLOMAT:
		# A scroll: a sheet between two rolls, lines of writing.
		ci.draw_rect(Rect2(c + Vector2(-0.5, -0.55) * s, Vector2(1.0, 1.1) * s), col, false, w)
		ci.draw_circle(c + Vector2(-0.5, -0.55) * s, 0.16 * s, col)
		ci.draw_circle(c + Vector2(0.5, -0.55) * s, 0.16 * s, col)
		ci.draw_circle(c + Vector2(-0.5, 0.55) * s, 0.16 * s, col)
		ci.draw_circle(c + Vector2(0.5, 0.55) * s, 0.16 * s, col)
		for k in 3:
			ci.draw_line(c + Vector2(-0.3, -0.25 + 0.25 * k) * s, c + Vector2(0.3, -0.25 + 0.25 * k) * s, col, w * 0.6, true)
	else:
		# A crown: band, three points, a jewel on each.
		ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-0.75, 0.55) * s, c + Vector2(0.75, 0.55) * s,
			c + Vector2(0.75, -0.45) * s, c + Vector2(0.38, 0.05) * s, c + Vector2(0, -0.6) * s,
			c + Vector2(-0.38, 0.05) * s, c + Vector2(-0.75, -0.45) * s]), col)
		for x in [-0.75, 0.0, 0.75]:
			ci.draw_circle(c + Vector2(x, -0.62 if x == 0.0 else -0.5) * s, 0.12 * s, col)
		# His field under the crown: a small mark by kind (foot, bow, horse, engine).
		var mk := [Vector2(-0.3, 0.75), Vector2(-0.1, 0.75), Vector2(0.1, 0.75), Vector2(0.3, 0.75)]
		for k in clampi(kind, 1, 4):
			ci.draw_circle(c + mk[k] * s, 0.07 * s, col)


## Unit markers at the centroid: side colour, white ring when selected,
## yellow when routing, plus small state signs.
func _draw_markers(r: float, lw: float) -> void:
	var tick: int = sim.tick
	hit_src = _hit_source()
	_lp = logical_px()
	var chs: bool = sim.ch_on != 0
	var vis: bool = sim.vis_on != 0
	for u in sim.n_units:
		if sim.u_state[u] >= BattleSim.U_DESTROYED:
			continue
		if (chs or vis) and sim.hidden_from(u, player_side):
			continue  # (the enemy's hidden assassin, a unit we do not see: not drawn)
		var anc := to_px(sim.u_cx[u], sim.u_cy[u])
		_up(anc)
		var c := anc + Vector2(0, -marker_dy(r) - TrayLayer.wall_lift(sim, u))   # (a unit on a wall walk: up with its men)
		var col: Color = COL_SIDE[sim.u_side[u]]
		if sim.u_state[u] == BattleSim.U_ROUTING:
			col = Color(1.0, 0.9, 0.3)
		# Unit type symbol on a disc in the side colour (yellow when broken,
		# with a dark glyph for contrast).
		var glyph := Color(0.12, 0.1, 0.05) if sim.u_state[u] == BattleSim.U_ROUTING else Color.WHITE
		if chs and sim.u_char[u] != 0:
			_draw_char_marker(u, c, r, col, lw)
		else:
			Icons.draw_marker(self, _icon[u], c, r, col, glyph)
		if u == match_u:
			var mc := c + Vector2(r * 2.0, 0)
			var mcol := Color(0.3, 0.9, 0.35) if match_v > 0 else (Color(1.0, 0.3, 0.25) if match_v < 0 else Color(0.7, 0.7, 0.7))
			var dy := -1.0 if match_v > 0 else 1.0
			var pts := PackedVector2Array([mc + Vector2(0, dy * r * 0.7), mc + Vector2(-r * 0.7, -dy * r * 0.5), mc + Vector2(r * 0.7, -dy * r * 0.5)])
			if match_v == 0:
				pts = PackedVector2Array([mc + Vector2(-r * 0.5, 0), mc + Vector2(0, -r * 0.5), mc + Vector2(r * 0.5, 0), mc + Vector2(0, r * 0.5)])
			draw_colored_polygon(pts, mcol)
			draw_polyline(pts + PackedVector2Array([pts[0]]), Color(0, 0, 0, 0.8), lw)
		if selected_units.has(u):
			draw_arc(c, r * 1.6, 0, TAU, 20, Color.WHITE, lw)
		if not group_tags.is_empty() and group_tags.has(u) and sim.u_side[u] == player_side:
			var gtx: String = group_tags[u]
			var gfs := _font_size(11.0)
			var gtw := ThemeDB.fallback_font.get_string_size(gtx, HORIZONTAL_ALIGNMENT_LEFT, -1, gfs).x
			var gat := c + Vector2(r * 0.75, -r * 1.05)
			draw_rect(Rect2(gat + Vector2(-2, -gfs), Vector2(gtw + 5, gfs + 3)), Color(0.08, 0.07, 0.04, 0.85))
			_dstr(gat, gtx, HORIZONTAL_ALIGNMENT_LEFT, -1, gfs, Color(1.0, 0.85, 0.35))
		if sim.u_state[u] == BattleSim.U_READY:
			_draw_cover_chip(u, c, r, lw)
		if hit_src >= 0 and sim.u_side[u] != sim.u_side[hit_src]:
			_draw_hit_mark(u, c, r, lw)
		if sim.car_on != 0 and sim.u_car[u] != 0:
			# The caracole's phase under the marker (Firing / Wheeling / Reloading 18 s).
			var ctx := Traits.caracole_text(sim, u)
			if ctx != "":
				var cfs := _font_size(11.0)
				var ctw := ThemeDB.fallback_font.get_string_size(ctx, HORIZONTAL_ALIGNMENT_LEFT, -1, cfs).x
				var cat := c + Vector2(-ctw * 0.5, r * 2.5)
				draw_rect(Rect2(cat + Vector2(-3, -cfs), Vector2(ctw + 6, cfs + 4)), Color(0, 0, 0, 0.6))
				_dstr(cat, ctx, HORIZONTAL_ALIGNMENT_LEFT, -1, cfs, Color(1.0, 0.88, 0.5))
		if vis and tick - sim.u_revt[u] < REVEAL_FX:
			# Seen after hiding (it shot or broke cover): a ring that
			# spreads and fades from the marker.
			var f := float(tick - sim.u_revt[u]) / REVEAL_FX
			draw_arc(c, r * (1.3 + 2.2 * f), 0, TAU, 24, Color(1.0, 0.95, 0.6, 0.9 * (1.0 - f)), lw * (2.0 - f))
		if sim.u_state[u] != BattleSim.U_READY:
			continue
		if vis and sim.u_side[u] == player_side:
			_draw_cover_mark(u, c, r, lw)
		# Under missile fire: orange ring for a second after each wound.
		if tick - sim.u_hit_t[u] < 10:
			draw_arc(c, r * 1.25, 0, TAU, 16, Color(1.0, 0.6, 0.1, 0.9), lw)
		# Hit by a charge: red flash.
		if tick - sim.u_charged_t[u] < 15:
			draw_arc(c, r * 1.45, 0, TAU, 16, Color(1, 0.15, 0.1, 0.95), lw * 1.3)
		# Charging cavalry: chevron ahead of the marker.
		if sim.u_mom[u] >= BattleSim.CHARGE_MIN:
			var ang: float = sim.u_face[u] * TAU / 1024.0
			var f := Vector2(cos(ang), sin(ang))
			var s := Vector2(-f.y, f.x)
			var tip := c + f * r * 2.2
			draw_polyline(PackedVector2Array([tip - f * r * 0.8 + s * r * 0.7, tip,
				tip - f * r * 0.8 - s * r * 0.7]), Color.WHITE, lw * 1.2)
		# Artillery: a ring under the marker filling up while the battery
		# sets up (full = ready to shoot); empty while packed.
		if sim.u_neng[u] > 0:
			var full: int = UT.stat(sim.u_type[u], "deploy")
			var frac: float = float(sim.u_depl[u]) / maxf(full, 1.0)
			var rcol := Color(1, 0.9, 0.5, 0.95)
			if sim.u_rprog[u] > 0 or sim.u_refill[u] != 0:
				# Refilling: the ring shows how full the engines are (blue),
				# dashed while the battery gets into or out of it.
				var full_ammo: int = sim.u_neng[u] * UT.stat(sim.u_type[u], "m_ammo")
				frac = float(maxi(sim.u_ammo[u], 0)) / maxf(full_ammo, 1.0)
				rcol = Color(0.45, 0.8, 1.0, 0.95 if sim.u_rprog[u] >= BattleSim.REFILL_FULL else 0.5)
			var rc := c + Vector2(0, r * 1.9)
			draw_arc(rc, r * 0.45, 0, TAU, 12, Color(0, 0, 0, 0.6), lw)
			if frac > 0.0:
				draw_arc(rc, r * 0.45, -PI * 0.5, -PI * 0.5 + TAU * frac, 12, rcol, lw)
		# Braced spears / formed pikes: bar under the marker.
		if sim.u_braced[u] != 0:
			draw_line(c + Vector2(-r, r * 1.35), c + Vector2(r, r * 1.35), Color(1, 1, 1, 0.9), lw * 1.2)
		if sim.u_order[u] == BattleSim.O_WITHDRAW:
			var down := 1.0 if sim.u_side[u] == 0 else -1.0
			var b := c + Vector2(0, down * r * 2.0)
			draw_line(c + Vector2(0, down * r), b, COL_WITHDRAW, lw)
			draw_line(b, b + Vector2(-r * 0.5, -down * r * 0.5), COL_WITHDRAW, lw)
			draw_line(b, b + Vector2(r * 0.5, -down * r * 0.5), COL_WITHDRAW, lw)
	_flat()


## Tabletop pass 1: each unit's standard at its tray's rear-left corner (rear-right when it would sit on the unit marker) and
## the state tokens along the tray's front edge. Drawn in screen pixels (a transform of 1 / zoom about each anchor), so the
## sizes are the overworld's and stay readable; the marker disc stays where it was and is the only tap target.
func _draw_standards(r: float) -> void:
	var t0 := Time.get_ticks_usec()
	if _std_col.size() != sim.n_units:
		_std_prep()
	var w := 1.0 / zoom
	var sm := clampf(zoom, STD_MIN_SCALE, STD_MAX_SCALE)
	var tok_r := clampf(TOKEN_D * zoom, TOKEN_MIN, TOKEN_MAX) * 0.5
	var vr := _view_rect().grow(px_per_m * 12.0)
	var fogged: bool = sim.ch_on != 0 or sim.vis_on != 0
	var nq: int = trays.quads.size()
	var f := sm / Marks.BAKE_SM
	var o := Vector2(9.0, -8.0) * sm   # the pole's foot at the corner
	var tex_off := (o + Marks.BOX.position * sm - Vector2(Marks.BAKE_PAD, Marks.BAKE_PAD) * f) * w
	var tex_size := Marks.BAKE_SIZE * f * w
	# The standard's box (screen px about its pole foot) as an offset rectangle, for the marker test.
	var box_off := (o + Marks.BOX.position * sm) * w
	var box_size := Marks.BOX.size * sm * w
	var mr := r * 1.7
	for u in sim.n_units:
		var st: int = sim.u_state[u]
		if st > BattleSim.U_ROUTING:
			continue
		var q: PackedVector2Array
		if st == BattleSim.U_READY:
			if u >= nq:
				continue
			q = trays.quads[u]
			if q.is_empty():
				continue
		elif sim.u_alive[u] > 0:
			# Routed: the tray is lifted off; the standard stays with the men.
			var cc := to_px(sim.u_cx[u], sim.u_cy[u])
			q = PackedVector2Array([cc, cc, cc, cc + Vector2(-px_per_m * 2.0, 0)])
		else:
			continue
		if fogged and sim.hidden_from(u, player_side):
			continue
		var corner := q[3]
		if not vr.has_point(corner):
			continue
		var wl := TrayLayer.wall_lift(sim, u)
		var mc := to_px(sim.u_cx[u], sim.u_cy[u]) + Vector2(0, -marker_dy(r) - wl)
		if st == BattleSim.U_READY and _box_hits(corner + box_off, box_size, mc, mr):
			var alt := q[2]
			if not _box_hits(alt + box_off, box_size, mc, mr):
				corner = alt
		var sel := selected_units.has(u)
		var ci: int = u * 2 + (1 if sel else 0)
		var stex: Texture2D = _std_tex[ci]
		if stex == null:
			stex = Marks.standard_tex(_std_col[u], sel, sim.u_side[u] == player_side, str(u + 1), _std_emb[u])
			_std_tex[ci] = stex
		_up(corner)
		var lf := Vector2(0, -wl)
		if stex == null:
			Marks.draw_standard_tex(self, null, corner + o * w + lf, sm * w, _std_col[u])
		else:
			draw_texture_rect(stex, Rect2(corner + tex_off + lf, tex_size), false)
		_flat()
		if st != BattleSim.U_READY:
			continue
		var toks := _tokens(u)
		if toks.is_empty():
			continue
		var dirv := q[1] - q[0]
		var len_w := dirv.length()
		dirv = dirv / maxf(len_w, 0.001)
		var rw := tok_r * w
		var fit := maxi(1, int((len_w - 0.4 * rw) / (2.4 * rw)))
		var half := Vector2.ONE * (Marks.TOK_PX * 0.5 / Marks.TOK_R * rw)
		for i in mini(toks.size(), fit):
			var tk: Array = toks[i]
			var tt: Texture2D = tk[2]
			if tt == null:
				tt = Marks.token_tex(str(tk[0]), tk[1])
				tk[2] = tt
			var tc: Vector2 = q[0] + dirv * (rw * 1.4 + rw * 2.4 * i)
			_up(tc)
			if tt == null:
				draw_circle(tc + lf, rw, tk[1])
			else:
				draw_texture_rect(tt, Rect2(tc - half + lf, half * 2.0), false)
			_flat()
	standards_us = Time.get_ticks_usec() - t0


## Each unit's pennant colour (its palette's primary: the men's main colour) and crest key, and the baked standards' slots.
func _std_prep() -> void:
	_std_col.clear()
	_std_emb.clear()
	_std_tex.clear()
	_std_tex.resize(sim.n_units * 2)
	for u in sim.n_units:
		_std_col.append(soldiers.pal_color(u) if soldiers != null else COL_SIDE[sim.u_side[u] & 1])
		var emblem := ""
		var f := int(soldiers.unit_faction[u]) if soldiers != null and u < soldiers.unit_faction.size() else -1
		if f >= 0 and f < CData.FACTIONS.size():
			emblem = str(CData.FACTIONS[f]["key"])
		_std_emb.append(emblem)


## Does the standard's box (top left p, size sz, world px) touch the marker circle?
func _box_hits(p: Vector2, sz: Vector2, mc: Vector2, mr: float) -> bool:
	var dx := mc.x - clampf(mc.x, p.x, p.x + sz.x)
	var dy := mc.y - clampf(mc.y, p.y, p.y + sz.y)
	return dx * dx + dy * dy < mr * mr


const TOKEN_BODY := {"hold_fire": Color(0.55, 0.2, 0.16), "stance_cover": Color(0.25, 0.4, 0.3), "stance_hold": Color(0.25, 0.32, 0.5),
	"stance_line": Color(0.3, 0.34, 0.42)}


## Unit u's state counters, the card strip's states first in its order (battle.gd `_card_states`: hold fire, a stance that is
## not the default, an ability on Hold or Use now), then out of ammunition, shaken, disordered. [glyph, body colour] each; only
## our own ready units (the enemy's orders are not ours to see).
func _tokens(u: int) -> Array:
	if sim.u_side[u] != player_side or sim.u_state[u] != BattleSim.U_READY:
		return []
	# (refreshed every 6th frame: the lists change with an order or a tick, not with the frame)
	var fr := Engine.get_frames_drawn()
	if _tok_at.size() != sim.n_units:
		_tok_at.resize(sim.n_units)
		_tok_at.fill(-100)
		_tok_cache.clear()
		_tok_cache.resize(sim.n_units)
	if fr - _tok_at[u] < 6 and fr >= _tok_at[u]:
		return _tok_cache[u]
	_tok_at[u] = fr
	var out := []
	if token_states.is_valid():
		for g in token_states.call(u):
			var gl := str(g[0])
			var body: Color = TOKEN_BODY.get(gl, Color(0.5, 0.2, 0.16) if gl.ends_with("!") else Color(0.36, 0.28, 0.1))
			out.append([gl, body, null])
	var ty: int = sim.u_type[u]
	if UT.stat(ty, "m_ammo") > 0 and sim.u_ammo[u] <= 0 and (sim.u_neng[u] == 0 or sim.u_reserve[u] <= 0):
		out.append(["ammo!", Color(0.42, 0.3, 0.1), null])
	var m: int = sim.u_morale[u] - sim.u_fright[u]
	if m < 450 and sim.u_order[u] != BattleSim.O_WITHDRAW:
		out.append(["shaken", Color(0.9, 0.74, 0.2), null])
	if sim.u_disorder[u] >= BattleSim.DISORDERED:
		out.append(["disordered", Color(0.74, 0.4, 0.14), null])
	_tok_cache[u] = out
	return out



## The last-seen ghosts: the men frozen where they were, greyed and fading
## over LastSeen.GHOST_FADE, then (and from the first moment) the footprint
## outline and a small greyed marker that stay until the unit is seen again.
## Never a target: nothing here is read by a tap. Low: no men.
func _draw_last_seen(r: float, lw: float) -> void:
	var now := Time.get_ticks_msec()
	var men_r := maxf(1.2, px_per_m * 0.32)
	for u in last_seen.recs:
		var g: Dictionary = last_seen.recs[u]
		var f: float = last_seen.fade(g, now)
		var mxs: PackedInt32Array = g["mx"]
		if f < 1.0 and not mxs.is_empty():
			var mys: PackedInt32Array = g["my"]
			var mc := Color(COL_GHOST, 0.55 * (1.0 - f))
			for i in mxs.size():
				draw_circle(to_px(mxs[i], mys[i]), men_r, mc)
		var edge := Color(COL_GHOST, lerpf(0.55, 0.2, f))
		_draw_footprint(u, to_px(g["ax"], g["ay"]), g["face"], g["files"], g["alive"], edge,
			Color(COL_GHOST, 0.1 * (1.0 - f)), lw)
		_up(to_px(g["x"], g["y"]))
		var c := to_px(g["x"], g["y"]) + Vector2(0, -marker_dy(r))
		var s := 0.8
		Icons.draw_marker(self, _icon[u], c, r * s, Color(COL_GHOST, lerpf(0.55, 0.38, f)),
			Color(1, 1, 1, lerpf(0.6, 0.45, f)))
		var fs := _font_size(10.0)
		_dstr(c + Vector2(-r * 1.4, r * 2.0), "last seen", HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
			Color(COL_GHOST, lerpf(0.7, 0.4, f)))
		_flat()


## Cover and line of fire, second pass (2026-11-06): world units per logical (CSS) pixel on screen now, for labels and
## marks that must stay readable on a phone (the canvas is stretched and zoomed).
func logical_px() -> float:
	var now := Time.get_ticks_msec()
	if now - _dpr_ms > 1000:
		_dpr_ms = now
		_dpr = UiScale.window_px_per_css(get_window()) if is_inside_tree() else 1.0
	# (The canvas transform has the camera's zoom; the viewport's final transform the window stretch.)
	var k := get_global_transform_with_canvas().get_scale().x * get_viewport().get_final_transform().get_scale().x \
		if is_inside_tree() else zoom
	return _dpr / maxf(k, 0.0001)


## A font size (world units) that reads at least `logical` CSS px on screen.
func label_fs(logical: float) -> int:
	return maxi(int(ceil(logical * logical_px())), 4)


## A label on a dark plate (readable over the red hatch of a house), upright in the oblique view.
func _plate_str(pos: Vector2, text: String, fs: int, col: Color) -> void:
	var font := ThemeDB.fallback_font
	var sz := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	var pad := fs * 0.3
	if BoardView.oblique and not _up_on:
		draw_set_transform_matrix(BoardView.up_xf(pos))
	draw_rect(Rect2(pos + Vector2(-pad, -fs - pad * 0.5), sz + Vector2(pad * 2.0, pad * 1.6)), Color(0.07, 0.06, 0.04, 0.82))
	draw_rect(Rect2(pos + Vector2(-pad, -fs - pad * 0.5), sz + Vector2(pad * 2.0, pad * 1.6)), Color(col, 0.6), false, maxf(fs * 0.06, 0.5))
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
	if BoardView.oblique and not _up_on:
		draw_set_transform_matrix(Transform2D.IDENTITY)


## The cover chip (2026-11-06, docs/design/ui.md "Cover chips and hittable marks"): every ready unit's marker carries a
## small shield at its upper left, green and whole for heavy cover, yellow and half filled for light, nothing in the open
## (third pass, 2026-11-06: the faint "none" ring went; Company of Heroes shows nothing for open ground), for what its
## troop type gets (BattleSim.cover_rating_front with cover_who). Rated against the enemy units that shot at it in the last
## CHIP_SHOT_T (BattleSim.cover_shooters; the worst of them), else the nearest enemy it sees (its facing with none); a
## house the shooter holds is no cover from its windows. A tick on the rim points at the threat rated. Held buildings and
## wall walks read heavy. Refreshed once a sim second.
const CHIP_SHOT_T := 30   # sim ticks: the shooters the chip is rated against (3 s)

func _draw_cover_chip(u: int, c: Vector2, r: float, lw: float) -> void:
	if UT.cls(sim.u_type[u]) == UT.CLS_ART or sim.is_ship(u) or (sim.ch_on != 0 and sim.u_char[u] != 0):
		return
	var e := chip_state(u)
	var cr: int = e[1]
	if cr == 0:
		return  # (open ground: no chip)
	var h := maxf(r * 0.95, 7.0 * _lp)   # (the shield at least 7 CSS px tall: 14 across on a phone)
	var w := h * 0.82
	var at := c + Vector2(-r - w * 0.7, -r * 0.55 - h * 0.45)
	var col := Color(0.45, 0.95, 0.4) if cr == 2 else Color(1.0, 0.84, 0.3)
	var top := at + Vector2(0, -h * 0.5)
	var pts := PackedVector2Array([at + Vector2(-w * 0.5, -h * 0.5), at + Vector2(w * 0.5, -h * 0.5),
		at + Vector2(w * 0.5, h * 0.05), at + Vector2(0, h * 0.5), at + Vector2(-w * 0.5, h * 0.05)])
	var ol := maxf(lw, 1.0 * _lp)
	var outer := PackedVector2Array()
	for p in pts:
		outer.append(at + (p - at) * 1.0 + (p - at).normalized() * ol * 1.6)
	draw_colored_polygon(outer, Color(0.05, 0.04, 0.02, 0.85))
	if cr == 2:
		draw_colored_polygon(pts, col)
	else:
		draw_colored_polygon(pts, Color(col, 0.28))
		# (light: its left half filled)
		draw_colored_polygon(PackedVector2Array([pts[0], top, at + Vector2(0, h * 0.5), pts[4]]), col)
	draw_polyline(pts + PackedVector2Array([pts[0]]), Color(col.lightened(0.3), 1.0), ol * 0.8)
	if int(e[2]) >= 0:
		var b: float = int(e[2]) * TAU / 1024.0
		var dv := Vector2(cos(b), sin(b) * (BoardView.OBLIQUE_COS if BoardView.oblique else 1.0)).normalized()
		var tang := Vector2(-dv.y, dv.x)
		var rr := h * 0.62
		var tip := at + dv * (rr + ol * 3.0)
		draw_colored_polygon(PackedVector2Array([tip, at + dv * rr + tang * h * 0.22, at + dv * rr - tang * h * 0.22]),
			Color(0.1, 0.08, 0.05, 0.95))


## Unit u's cover chip as drawn: [sim second, rating 0-2, threat bearing, BattleSim cover_who kind, the threat unit or
## -1] (cached a sim second).
func chip_state(u: int) -> Array:
	var sec: int = sim.tick / BattleSim.TICKS_PER_SECOND
	var e: Array = _chip.get(u, [])
	if e.is_empty() or int(e[0]) != sec:
		var rb := _chip_eval(u)
		e = [sec, rb[0], rb[1], sim.cover_who(u), rb[2]]
		_chip[u] = e
	return e


## The cover unit u has now, for its troop type, against its threats (_chip_threats): [rating, bearing, threat unit]:
## a held building or a wall's walk heavy; else the worst BattleSim.cover_rating_front along its front over the threats
## (a house a threat holds not counting against it); none: against its facing.
func _chip_eval(u: int) -> Array:
	var th := _chip_threats(u)
	var b0: int = sim.u_face[u] if th.is_empty() else _bearing(u, th[0])
	if (sim.occ_on != 0 and sim.u_occ[u] > 0) or sim.u_wall[u] > 0:
		return [2, b0, th[0] if not th.is_empty() else -1]
	var files: int = mini(sim.files_of(u), sim.u_alive[u])
	var hw: int = maxi(files - 1, 0) * UT.stat(sim.u_type[u], "file_sp") / 2
	var who: int = sim.cover_who(u)
	if th.is_empty():
		return [sim.cover_rating_front(sim.u_ax[u], sim.u_ay[u], b0, hw, who), b0, -1]
	var best := [3, b0, th[0]]
	for o in th:
		var b := _bearing(u, o)
		var cr: int = sim.cover_rating_front(sim.u_ax[u], sim.u_ay[u], b, hw, who, sim.held_building(o))
		if cr < int(best[0]):
			best = [cr, b, o]
	return best


## The enemy units unit u's chip is rated against: those that shot at it in the last CHIP_SHOT_T
## (BattleSim.cover_shooters), else the nearest enemy unit it sees within 250 m (centroids; index order on ties), else none.
func _chip_threats(u: int) -> PackedInt32Array:
	var sh: PackedInt32Array = sim.cover_shooters(u, CHIP_SHOT_T)
	if not sh.is_empty():
		return sh
	var side: int = sim.u_side[u]
	var best := -1
	var bd := 250 * 1024
	for o in sim.n_units:
		if sim.u_side[o] == side or sim.u_state[o] != BattleSim.U_READY or sim.hidden_from(o, side):
			continue
		var d := absi(sim.u_cx[o] - sim.u_cx[u]) + absi(sim.u_cy[o] - sim.u_cy[u])
		if d < bd:
			bd = d
			best = o
	return PackedInt32Array([best]) if best >= 0 else PackedInt32Array()


## The bearing (sim angle) from unit u's middle to unit o's.
func _bearing(u: int, o: int) -> int:
	return int(round(atan2(float(sim.u_cy[o] - sim.u_cy[u]), float(sim.u_cx[o] - sim.u_cx[u])) * 1024.0 / TAU)) & 1023


var _lp := 1.0      # this frame: world units per CSS px (logical_px)
var hit_src := -1   # this frame: the selected own missile unit whose targets get hittable / blocked marks (-1 none)

## The primary selection when it is this player's ready missile unit with shot left (its targets are marked), else -1.
func _hit_source() -> int:
	if selected_units.is_empty():
		return -1
	var u: int = selected_units[0]
	if u < 0 or u >= sim.n_units or sim.u_state[u] != BattleSim.U_READY or sim.u_side[u] != player_side \
			or UT.cls(sim.u_type[u]) != UT.CLS_MISSILE or sim.u_ammo[u] <= 0:
		return -1
	return u


## While a missile unit is selected (2026-11-06, CoH's sight cone as a per-enemy mark): each enemy in its range it sees
## gets a mark round its marker: four green ticks when it has a line of fire to it (BattleSim.lof_units: the sim's own
## unit-level answer, its middle and its men at cover spots), a struck red ring when a house, wall or crest is between.
## Cached per enemy per sim second.
func _draw_hit_mark(e: int, c: Vector2, r: float, lw: float) -> void:
	var hs := hit_state(hit_src, e)
	if hs < 0:
		return
	var rr := maxf(r * 1.75, 12.0 * _lp)
	lw = maxf(lw, 1.4 * _lp)
	if hs == 1:
		var gc := Color(0.5, 1.0, 0.45, 0.95)
		for k in 4:
			var a := PI * 0.25 + k * PI * 0.5
			var dv := Vector2(cos(a), sin(a))
			draw_line(c + dv * rr * 0.78, c + dv * rr * 1.22, Color(0, 0, 0, 0.75), lw * 2.6)
			draw_line(c + dv * rr * 0.78, c + dv * rr * 1.22, gc, lw * 1.3)
	else:
		var bc := Color(1.0, 0.3, 0.25, 0.95)
		draw_arc(c, rr, 0.0, TAU, 20, Color(0, 0, 0, 0.7), lw * 2.4)
		draw_arc(c, rr, 0.0, TAU, 20, bc, lw * 1.1)
		var dv := Vector2(cos(-PI * 0.25), sin(-PI * 0.25))
		draw_line(c - dv * rr, c + dv * rr, Color(0, 0, 0, 0.7), lw * 2.4)
		draw_line(c - dv * rr, c + dv * rr, bc, lw * 1.1)


## The mark enemy e gets while missile unit u is selected: 1 hittable, 0 blocked, -1 none (not ready, out of sight, out
## of u's range). The line from BattleSim.lof_units, cached per pair per sim second.
func hit_state(u: int, e: int) -> int:
	if u < 0 or e < 0 or sim.u_state[e] != BattleSim.U_READY or sim.hidden_from(e, sim.u_side[u]):
		return -1
	var dd := Vector2(sim.u_cx[e] - sim.u_cx[u], sim.u_cy[e] - sim.u_cy[u]).length()
	if dd > float(sim.range_vs(u, e)):
		return -1
	var sec: int = sim.tick / BattleSim.TICKS_PER_SECOND
	var key := u * 4096 + e
	var hv: Array = _hit.get(key, [])
	if hv.is_empty() or int(hv[0]) != sec:
		hv = [sec, 1 if sim.lof_units(u, e) else 0]
		_hit[key] = hv
	return int(hv[1])


## Own units (line of sight, docs/DESIGN.md "Cover and line of sight"): a
## leaf at the marker's lower left for a cover unit in cover (filled once it
## has gone to ground), and a closed eye at its lower right while the enemy
## does not see it.
func _draw_cover_mark(u: int, c: Vector2, r: float, lw: float) -> void:
	var cs: int = sim.cover_state(u)
	if cs > 0:
		var lc := c + Vector2(-r * 1.15, r * 0.95)
		var a := 0.95 if cs == 2 else 0.75
		var pts := PackedVector2Array([lc + Vector2(0, -r * 0.55), lc + Vector2(r * 0.32, 0), lc + Vector2(0, r * 0.55),
			lc + Vector2(-r * 0.32, 0)])
		if cs == 2:
			draw_colored_polygon(pts, Color(COL_COVER, a))
		draw_polyline(pts + PackedVector2Array([pts[0]]), Color(0, 0, 0, 0.7), lw * 1.6)
		draw_polyline(pts + PackedVector2Array([pts[0]]), Color(COL_COVER, a), lw)
		draw_line(lc + Vector2(0, -r * 0.45), lc + Vector2(0, r * 0.45), Color(0, 0, 0, 0.6), lw * 0.7)
	if sim.hidden_from(u, 1 - player_side) and player_side >= 0:
		var ec := c + Vector2(r * 1.15, r * 0.95)
		draw_arc(ec + Vector2(0, -r * 0.2), r * 0.42, PI * 0.15, PI * 0.85, 8, Color(0, 0, 0, 0.7), lw * 1.8)
		draw_arc(ec + Vector2(0, -r * 0.2), r * 0.42, PI * 0.15, PI * 0.85, 8, Color(0.85, 0.95, 1.0, 0.9), lw)


func _draw_selected(u: int, lw: float, r: float, primary: bool) -> void:
	var ty: int = sim.u_type[u]
	var files := mini(_fv(u), sim.u_alive[u])
	var half := (files - 1) * UT.stat(ty, "file_sp") / 2
	var a := to_px(_v(u, "ax"), _v(u, "ay"))
	if sim.phase == BattleSim.PHASE_DEPLOY and sim.u_carry[u] < 0 and _v(u, "pick") >= 0 \
			and _v(u, "pick") < sim.n_eq:
		# Deployment pick-up pending: the pair, the unit in its carry pattern
		# at the piece.
		_draw_footprint(u, a, _v(u, "face"), files, sim.u_alive[u], Color(0.6, 1.0, 1.0, 0.95),
			Color(0.6, 1.0, 1.0, 0.16), lw)
	_draw_mantlet_cover(u, lw, primary)
	var ang: float = _v(u, "face") * TAU / 1024.0
	var fwd := Vector2(cos(ang), sin(ang))
	var right := Vector2(-fwd.y, fwd.x)
	var hw := half * px_per_m / M
	draw_line(a - right * hw, a + right * hw, Color(1, 1, 1, 0.8), lw)
	draw_line(a, a + fwd * px_per_m * 3.0, Color(1, 1, 1, 0.8), lw)
	var order: int = _v(u, "order")
	var wp: Dictionary = orders.wall_plan(u) if orders != null else {}
	if not wp.is_empty():
		_draw_wall_plan(u, wp, lw, primary)
		if wp["mode"] == "up" or wp["mode"] == "down" or wp["mode"] == "ladder":
			order = -1  # its way is the plan's (by the stair or ladders), not a straight line
			if wp["mode"] == "down" and int(wp["seg"]) < 0 and _v(u, "order") == BattleSim.O_MOVE:
				# Where it forms up below (its normal block).
				_draw_footprint(u, to_px(_v(u, "dx"), _v(u, "dy")), _v(u, "dface"), _v(u, "files"),
					sim.u_alive[u], Color(0.6, 1.0, 0.6, 0.9), Color(0.6, 1.0, 0.6, 0.14), lw)
	if order == BattleSim.O_MOVE:
		var d := to_px(_v(u, "dx"), _v(u, "dy"))
		var dang: float = _v(u, "dface") * TAU / 1024.0
		var dfwd := Vector2(cos(dang), sin(dang))
		var dright := Vector2(-dfwd.y, dfwd.x)
		var srt: Dictionary = orders.order_route(u) if orders != null else {}
		if not srt.is_empty() and not srt["blocked"] and (srt["pts"] as PackedInt32Array).size() > 4:
			_draw_route(srt["pts"], Color(0.6, 1.0, 0.6, 0.9), lw, false)
		else:
			_dash_outlined(a, d, Color(0.6, 1.0, 0.6, 0.85), lw, 8.0 / zoom)
		_draw_woods_along(_v(u, "ax"), _v(u, "ay"), _v(u, "dx"), _v(u, "dy"), lw)
		draw_line(d - dright * hw, d + dright * hw, Color(0, 0, 0, 0.4), lw * 3.0)
		draw_line(d - dright * hw, d + dright * hw, Color(0.6, 1.0, 0.6, 0.9), lw * 1.5)
		draw_line(d, d + dfwd * px_per_m * 3.0, Color(0.6, 1.0, 0.6, 0.9), lw)
		if primary:
			_draw_slope_hint(sim.u_h[u], sim.height_at(_v(u, "dx"), _v(u, "dy")),
				_v(u, "dx") - sim.u_cx[u], _v(u, "dy") - sim.u_cy[u], d + Vector2(r, r * 1.2),
				sim.u_cx[u], sim.u_cy[u])
			if _v(u, "pick") >= 0 and _v(u, "pick") < sim.n_eq:
				var pk: int = sim.q_kind[_v(u, "pick")]
				var ptxt := "PICK UP THE RAM" if pk == BattleSim.EQ_RAM else "PICK UP LADDERS"
				if pk == BattleSim.EQ_POLES:
					ptxt = "PICK UP POLES"
				elif pk == BattleSim.EQ_WAGON:
					ptxt = "TAKE THE WAGON"
				elif BattleSim.EQ_SCREEN[pk] != 0:
					ptxt = "PICK UP THE MANTLET"
				elif BattleSim.EQ_EXPOSED[pk] != 0:
					ptxt = "PUSH THE SIEGE TOWER"
				_dstr(d + Vector2(r, -r * 1.5), ptxt,
					HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size(13.0), Color(1.0, 0.8, 0.45))
			elif _v(u, "pick") >= BattleSim.PICK_ENG:
				var eg: int = _v(u, "pick") - BattleSim.PICK_ENG
				var etxt := "TAKE UP THE BOLT THROWERS" if UT.stat(sim.eg_type[eg], "m_kind") == 1 else "TAKE UP THE STONE THROWERS"
				_dstr(d + Vector2(r, -r * 1.5), etxt,
					HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size(13.0), Color(1.0, 0.8, 0.45))
			elif _v(u, "gtarget") >= 0 and sim.u_cls[u] == UT.CLS_MISSILE:
				_dstr(d + Vector2(r, -r * 1.5), "SHOOT THE GATE ALIGHT",
					HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size(13.0), Color(1.0, 0.65, 0.3))
			elif _v(u, "gtarget") >= 0:
				var gtxt := "BREAK THE GATE"
				if BattleSim.carrying(sim, u) == BattleSim.EQ_RAM:
					gtxt = "RAM THE GATE"
				elif sim.gate_frame(_v(u, "gtarget"), _v(u, "dx"), _v(u, "dy")).y < 0:
					gtxt = "UNBAR THE GATE"  # ladder men inside the walls
				_dstr(d + Vector2(r, -r * 1.5), gtxt,
					HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size(13.0), Color(1.0, 0.8, 0.45))
			elif orders != null and orders.snap_of(u) >= 2:
				_dstr(d + Vector2(r, -r * 1.5),
					"NO WAY IN: MOVING TO THE GATE" if orders.snap_of(u) == 2 else "NO WAY THERE",
					HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size(13.0), Color(1.0, 0.8, 0.45))
	elif order == BattleSim.O_ATTACK and _v(u, "target") >= 0:
		var t: int = _v(u, "target")
		var tcol := Color(1, 0.3, 0.2, 0.85)
		var shooter: bool = UT.stat(ty, "m_ammo") > 0 and sim.u_ammo[u] > 0
		if shooter:
			tcol = COL_FIRE
		var tp := to_px(sim.u_cx[t], sim.u_cy[t])
		var ug := Vector3i.ZERO
		if sim.city_on != 0 and sim.u_wall[u] == 0:
			ug = sim.unreach_goal(u, t, sim._attack_goal(u, t))
			if ug.z == 1 and shooter and sim._in_range(u, t, sim.range_vs(u, t)):
				ug = Vector3i.ZERO  # in range already: it shoots from where it stands
		if ug.z != 0:
			# Out of reach: its way to the gate (melee) or into range (missiles).
			var gp := to_px(ug.x, ug.y)
			_dash_outlined(a, gp, Color(1.0, 0.8, 0.45, 0.9), lw, 8.0 / zoom)
			_dd(gp, tp, Color(tcol, 0.35), lw, 4.0 / zoom)
			if primary:
				var into := "MOVING INTO RANGE"
				if shooter and sim.lob_over_wall(u, t):
					into = "TOO FAR TO LOB OVER THE WALL: MOVING CLOSER" if sim.wall_cross_at(sim.u_cx[u], sim.u_cy[u],
						sim.u_cx[t], sim.u_cy[t]) >= 0 else "TOO FAR TO LOB OVER THE HOUSES: MOVING CLOSER"
				_dstr(gp + Vector2(r, -r * 1.5),
					"NO WAY IN: TO THE GATE" if ug.z == 2 else into,
					HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size(13.0), Color(1.0, 0.8, 0.45))
		elif shooter and sim.vis_on != 0 and sim.hidden_from(t, sim.u_side[u]):
			# Line of sight: the target is out of sight (flat weapons hold,
			# arrows are lobbed blind at where it was).
			# (No line to it: where it is now is not known.)
			var arc_w: bool = UT.stat(ty, "m_arc") != 0
			if primary:
				_dstr(a + Vector2(r, r * 2.5), "TARGET OUT OF SIGHT: SHOOTING BLIND" if arc_w \
					else "TARGET OUT OF SIGHT: HOLDING FIRE", HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size(12.0), COL_BLOCKED)
		elif not (shooter and _draw_blocked(u, t, lw)):
			_dash_outlined(a, tp, tcol, lw, 8.0 / zoom)
		if primary and not shooter:
			_draw_slope_hint(sim.u_h[u], sim.u_h[t], sim.u_cx[t] - sim.u_cx[u],
				sim.u_cy[t] - sim.u_cy[u], (a + tp) * 0.5, sim.u_cx[u], sim.u_cy[u])
	elif order == BattleSim.O_ATTACK and _v(u, "gtarget") >= 0 and sim.n_gates > _v(u, "gtarget"):
		# A battery shooting at a gate.
		var gf: Vector2i = sim.gate_face(_v(u, "gtarget"))
		_dd(a, to_px(gf.x, gf.y), COL_FIRE, lw, 8.0 / zoom)
		if primary:
			_dstr(to_px(gf.x, gf.y) + Vector2(r, r), "SHOOT THE GATE",
				HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size(13.0), COL_FIRE)
	elif order == BattleSim.O_WITHDRAW:
		_draw_withdraw(u, a, COL_WITHDRAW, lw)
	if orders != null:
		var ch: Array = orders.chain(u)
		if not ch.is_empty():
			_draw_chain(u, ch, lw, primary)
	# Artillery: firing arc between minimum and maximum range (and the full
	# range faintly, since the battery can turn), and its current target.
	if UT.cls(ty) == UT.CLS_ART:
		_draw_art_range(u, lw)
		_draw_fire_line(u, lw)
	# Missile troops: range circle (stretched where the ground falls away,
	# shortened uphill) and what they are shooting at now.
	if UT.cls(ty) == UT.CLS_MISSILE:
		var rcol := Color(1.0, 0.85, 0.4, 0.45) if sim.u_ammo[u] > 0 else Color(0.6, 0.6, 0.6, 0.3)
		_draw_range(u, 0.0, TAU, rcol, lw)
		_draw_fire_line(u, lw)
	if primary and _v(u, "run") != 0:
		_dstr(a + Vector2(r, -r * 3.5), "RUN",
			HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size(14.0), Color.WHITE)


## Firing arc of battery u: an annular sector from minimum to maximum range,
## +-arc about its facing (the facing it is turning to, if pending), plus the
## whole maximum-range circle faintly.
func _draw_art_range(u: int, lw: float) -> void:
	var ty: int = sim.u_type[u]
	var c := to_px(sim.u_cx[u], sim.u_cy[u])
	var k := px_per_m / M
	var rmin := UT.stat(ty, "m_min") * k
	var ok: bool = sim.u_ammo[u] > 0
	var col := COL_ARC if ok else Color(0.6, 0.6, 0.6, 0.3)
	_draw_range(u, 0.0, TAU, Color(col, col.a * 0.35), lw)
	if rmin > 0.0:
		_da(c, rmin, 0, TAU, 48, Color(col, col.a * 0.35), lw)
	var face: float = _v(u, "dface") * TAU / 1024.0
	var half: float = UT.stat(ty, "arc") * TAU / 1024.0
	var a0 := face - half
	var a1 := face + half
	var ends := _draw_range(u, a0, a1, col, lw * 1.6)
	_da(c, maxf(rmin, px_per_m), a0, a1, 12, col, lw * 1.6)
	for e in 2:
		var a: float = [a0, a1][e]
		var d := Vector2(cos(a), sin(a))
		_dl(c + d * maxf(rmin, px_per_m), ends[e], col, lw)


## Stone impacts in the last FX_TICKS ticks: a dust ring that spreads and
## fades, and the furrow the stone ploughed on along its flight.
func _draw_impacts(lw: float) -> void:
	var now: float = sim.tick
	for k in sim.fx_t.size():
		var age: float = now - sim.fx_t[k]
		if age < 0.0 or age > FX_TICKS:
			continue
		var f := age / FX_TICKS
		var p := to_px(sim.fx_x[k], sim.fx_y[k])
		var dir := Vector2(sim.fx_dx[k], sim.fx_dy[k]) / 4096.0
		var a := 0.85 * (1.0 - f)
		# A stone that landed on a wall walk (or a tower), in a held building or on a siege tower lands there, at the height
		# the men on it are drawn at (SoldierLayer.point_dm).
		var up_h := 0.0
		if BoardView.oblique and sim.obs_on != 0:
			up_h = float(SoldierLayer.point_dm(sim, sim.fx_x[k], sim.fx_y[k])) * 0.1 * px_per_m * BoardView.OBLIQUE_SIN
		_up(p)
		draw_circle(p + Vector2(0, -up_h - px_per_m * (0.6 + 1.8 * f) * 0.5 if BoardView.oblique else 0.0), px_per_m * (0.6 + 1.8 * f), Color(0.55, 0.45, 0.32, a * 0.55))
		if up_h > 0.0:
			draw_arc(p + Vector2(0, -up_h), px_per_m * (1.0 + 2.5 * f), 0, TAU, 16, Color(0.85, 0.75, 0.55, a), lw)
			_flat()
			continue
		_flat()
		draw_arc(p, px_per_m * (1.0 + 2.5 * f), 0, TAU, 16, Color(0.85, 0.75, 0.55, a), lw)
		draw_line(p, p + dir * px_per_m * 8.0, Color(0.35, 0.27, 0.18, a), maxf(lw * 1.5, px_per_m * 0.5))


## A dashed order line over a faint dark underlay, so it reads on light and
## dark ground alike.
func _dash_outlined(a: Vector2, b: Vector2, col: Color, w: float, dash: float) -> void:
	_dl(a, b, Color(0, 0, 0, 0.32), w * 2.6)
	_dd(a, b, col, w, dash)


func _draw_fire_line(u: int, w: float) -> void:
	var t: int = sim.u_ftarget[u]
	if t < 0 or sim.u_state[t] >= BattleSim.U_DESTROYED:
		return
	_dd(to_px(sim.u_cx[u], sim.u_cy[u]), to_px(sim.u_cx[t], sim.u_cy[t]),
		COL_FIRE, w, 4.0 / zoom)


## Missile range of unit u from angle a0 to a1 (radians): on hilly ground
## each point is the type's range against the ground under that point
## (two refinements of radius -> ground height -> range), so the ring
## bulges out where the ground falls away and pulls in uphill. Returns the
## end points (for the artillery sector edges).
func _draw_range(u: int, a0: float, a1: float, col: Color, w: float) -> Array:
	var ty: int = sim.u_type[u]
	var cx: int = sim.u_cx[u]
	var cy: int = sim.u_cy[u]
	var rng: int = UT.stat(ty, "m_range")
	var c := to_px(cx, cy)
	var full := a1 - a0 >= TAU - 0.001
	var steps := RANGE_STEPS if full else maxi(int(RANGE_STEPS * (a1 - a0) / TAU) + 2, 4)
	var pts := PackedVector2Array()
	var lob: bool = sim.lobber(u)
	var hcut := _house_cut(u, rng) if full and not lob else PackedInt32Array()
	for k in steps + 1:
		var ang := a0 + (a1 - a0) * k / steps
		var dir := Vector2(cos(ang), sin(ang))
		var r := rng
		if sim.ter_on != 0 or sim.obs_on != 0:
			for it in 2:
				var px := cx + int(dir.x * r)
				var py := cy + int(dir.y * r)
				r = sim.range_h(ty, sim.u_h[u], sim.height_at(px, py))
		if lob:
			# Over a wall the arrows are lobbed: ARC_OVER_WALL_PCT of the range
			# beyond it (up to the wall in full where the cut range falls short of it).
			var dw: int = sim.wall_cross_at(cx, cy, cx + int(dir.x * r), cy + int(dir.y * r))
			if dw >= 0:
				r = maxi(r * BattleSim.ARC_OVER_WALL_PCT / 100, dw)
		elif full and hcut.size() > k:
			r = mini(r, hcut[k])  # (a flat weapon's ring pulled in to the house, wall or tower in the way: 2026-11-06)
		pts.append(c + dir * (r * px_per_m / M))
	if full and not _up_on:
		# The range ring is a brass rule (a grey one when the ammunition is gone): `col`'s alpha says how strong.
		var strong := clampf(col.a / 0.45, 0.0, 1.0)
		BrassRule.band(self, pts, px_per_m, zoom, sim.u_ammo[u] > 0, lerpf(0.55, 1.0, strong))
		var al := lerpf(0.55, 1.0, strong)
		BrassRule.ticks(self, pts, c, px_per_m, zoom, Callable(self, "_rule_label"), al, false)
		# (A ring's numbers would be lengths along the circle: one label with its range, at the top, instead.)
		if pts.size() > 54:
			var top := pts[54]
			_rule_label(top + Vector2(0.0, BrassRule.width_px(px_per_m, zoom) * 1.6), "%d m" % int(round(float(rng) / M)),
				maxf(5.0, 11.0 / zoom), Color(BrassRule.BRASS_HI if sim.u_ammo[u] > 0 else Color(0.9, 0.92, 0.95), 0.95 * al))
	else:
		_dp(pts, col, w)
	return [pts[0], pts[pts.size() - 1]]


## A flat missile weapon's range ring cut where houses block (2026-11-06): per ring step (RANGE_STEPS + 1 rays from the
## unit's middle) the distance to the face of the first house, wall, tower or shut gate in the way
## (BattleSim.lof_works_block, the sim's own line), `rng` where none; cached per unit per sim second. Empty: no cut (arcing
## weapons, engines, a map without obstacles, a unit on a wall's walk or in a building).
func _house_cut(u: int, rng: int) -> PackedInt32Array:
	var ty: int = sim.u_type[u]
	if sim.obs_on == 0 or UT.stat(ty, "m_arc") != 0 or UT.cls(ty) != UT.CLS_MISSILE or sim.u_wall[u] > 0 \
			or (sim.occ_on != 0 and sim.u_occ[u] > 0):
		return PackedInt32Array()
	var sec: int = sim.tick / BattleSim.TICKS_PER_SECOND
	var cx: int = sim.u_cx[u]
	var cy: int = sim.u_cy[u]
	var e: Array = _ring.get(u, [])
	if not e.is_empty() and int(e[0]) == sec and int(e[1]) == cx and int(e[2]) == cy:
		return e[3]
	var out := PackedInt32Array()
	out.resize(RANGE_STEPS + 1)
	for k in RANGE_STEPS + 1:
		var ang := TAU * k / RANGE_STEPS
		var ex := cx + int(cos(ang) * rng)
		var ey := cy + int(sin(ang) * rng)
		var b: int = sim.lof_works_block(u, cx, cy, ex, ey)
		out[k] = b if b >= 0 else rng
	out = _ring_open(out)
	_ring[u] = [sec, cx, cy, out]
	return out


## The cut ring without its spikes (third pass, 2026-11-06: rays down a street reached the full range between houses a
## few metres off and drew long orange spikes that read as paths): a grey-scale opening over the ring steps (the least
## within RING_OPEN steps either side, then the most of those), so a reach narrower than 2 RING_OPEN + 1 steps (25
## degrees) is pulled in to its neighbours while wider open sectors and every cut stay. Last step = first (a closed ring).
const RING_OPEN := 2

func _ring_open(r: PackedInt32Array) -> PackedInt32Array:
	var n := r.size() - 1
	if n < 2 * RING_OPEN + 1:
		return r
	var mn := PackedInt32Array()
	mn.resize(n)
	for k in n:
		var m := r[k]
		for j in range(-RING_OPEN, RING_OPEN + 1):
			m = mini(m, r[(k + j + n) % n])
		mn[k] = m
	var out := PackedInt32Array()
	out.resize(n + 1)
	for k in n:
		var m := mn[k]
		for j in range(-RING_OPEN, RING_OPEN + 1):
			m = maxi(m, mn[(k + j + n) % n])
		out[k] = m
	out[n] = out[0]
	return out


## Flat weapons on hilly ground: if the line of fire from u to t is blocked
## by a crest, draw it broken and red up to the crest with a cross there,
## and faintly beyond. Returns true if it was blocked (and drawn).
func _draw_blocked(u: int, t: int, w: float) -> bool:
	var ty: int = sim.u_type[u]
	if (sim.ter_on == 0 and sim.map_on == 0) or UT.stat(ty, "m_arc") != 0 or sim.lof_units(u, t):
		return false
	var x0: int = sim.u_cx[u]
	var y0: int = sim.u_cy[u]
	var x1: int = sim.u_cx[t]
	var y1: int = sim.u_cy[t]
	var dist := maxf(Vector2(x1 - x0, y1 - y0).length(), 1.0)
	var apex: int = int(dist) * UT.stat(ty, "m_apex") / 100
	var blk: int = sim.lof_block(x0, y0, sim.u_h[u] + BattleSim.LOF_EYE, x1, y1,
		sim.u_h[t] + BattleSim.LOF_BODY, apex, 0, BattleSim.LOF_STEP, sim._skip0(u), sim._skip1(t))
	var a := to_px(x0, y0)
	var b := to_px(x1, y1)
	var crest := a.lerp(b, clampf(blk / dist, 0.05, 0.95)) if blk >= 0 else (a + b) * 0.5
	_dd(a, crest, COL_BLOCKED, w * 1.3, 10.0 / zoom, false)
	_dd(crest, b, Color(COL_BLOCKED, 0.3), w, 4.0 / zoom)
	var s := 9.0 / zoom
	draw_line(crest + Vector2(-s, -s), crest + Vector2(s, s), COL_BLOCKED, w * 2.0)
	draw_line(crest + Vector2(-s, s), crest + Vector2(s, -s), COL_BLOCKED, w * 2.0)
	# Buildings block a flat shot (2026-11-06): with an attack order it walks round to the spot with a line (the sim's
	# fire_spot), drawn as its way there.
	var sp: Vector3i = _fire_spot_steady(u, t) if sim.u_order[u] == BattleSim.O_ATTACK and sim.u_target[u] == t \
		and blk >= 0 and sim.lof_works_block(u, x0, y0, x1, y1, true) >= 0 else Vector3i.ZERO
	if sp.z != 0:
		var spx := to_px(sp.x, sp.y)
		_dash_outlined(a, spx, Color(1.0, 0.8, 0.45, 0.9), w, 8.0 / zoom)
		draw_arc(spx, px_per_m * 1.2, 0, TAU, 14, Color(1.0, 0.8, 0.45, 0.95), w * 1.5)
		_dd(spx, b, Color(COL_FIRE, 0.6), w, 4.0 / zoom)
	# (Second pass, 2026-11-06: on a dark plate at a readable size, at least 12 CSS px; from the kept spot, steady.)
	var fs := maxi(_font_size(12.0), label_fs(12.0))
	_plate_str(crest + Vector2(s * 1.4, -s * 0.6), "NO LINE OF FIRE: MOVING AROUND" if sp.z != 0 else "NO LINE OF FIRE",
		fs, Color(1.0, 0.45, 0.38))
	return true


## The order preview's fire spot (2026-11-06): the sim's kept one when it has one (steady: it changes only when the sim
## keeps another), else BattleSim.fire_spot once a sim second (not every frame).
func _fire_spot_steady(u: int, t: int) -> Vector3i:
	if sim.u_fst.size() > u and sim.u_fst[u] == t + 1:
		return sim.fire_spot_view(u, t)
	var sec: int = sim.tick / BattleSim.TICKS_PER_SECOND
	var key := u * 4096 + t
	var e: Array = _fsv.get(key, [])
	if e.is_empty() or int(e[0]) != sec:
		e = [sec, sim.fire_spot_view(u, t)]
		_fsv[key] = e
	return e[1]


## "uphill 12%" / "downhill 9%" from ground height ha to hb over (dx, dy)
## (sim units), at `at` (world pixels); nothing on gentle ground. "woods"
## (or "dense woods") when the way from (x0, y0) runs through trees.
func _draw_slope_hint(ha: int, hb: int, dx: int, dy: int, at: Vector2, x0: int = -1, y0: int = -1) -> void:
	var parts: Array[String] = []
	var col := COL_WOODS
	if sim.ter_on != 0:
		var d := maxf(Vector2(dx, dy).length(), 1.0)
		var g := int((hb - ha) * 4096.0 / maxf(d, 1024.0))
		if absi(g) >= HINT_GRADE:
			var pct := absi(g) * 100 / 4096
			parts.append(("uphill %d%%" % pct) if g > 0 else ("downhill %d%%" % pct))
			col = COL_UPHILL if g > 0 else COL_DOWNHILL
	if sim.veg_on != 0 and x0 >= 0:
		var w := _woods_on(x0, y0, x0 + dx, y0 + dy)
		if w > 0:
			parts.append("dense woods" if w >= 3 else "woods")
	if parts.is_empty():
		return
	_dstr(at, ", ".join(parts), HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size(13.0), col)


## Densest woods on the line (sim units), sampled every 4 m (0 none).
func _woods_on(x0: int, y0: int, x1: int, y1: int) -> int:
	var l := Vector2(x1 - x0, y1 - y0).length()
	var n := int(l / 4096.0) + 1
	var best := 0
	for q in n + 1:
		var x := x0 + int((x1 - x0) * q / float(n))
		var y := y0 + int((y1 - y0) * q / float(n))
		best = maxi(best, sim.veg_d(x, y))
	return best


## Where a move line runs through woods: drawn over in green (stronger for
## denser woods), with a dot where it enters or leaves the trees.
func _draw_woods_along(x0: int, y0: int, x1: int, y1: int, lw: float) -> void:
	if sim.veg_on == 0:
		return
	var l := Vector2(x1 - x0, y1 - y0).length()
	var n := int(l / 4096.0) + 1
	var prev: int = sim.veg_d(x0, y0)
	var pa := to_px(x0, y0)
	for q in range(1, n + 1):
		var x := x0 + int((x1 - x0) * q / float(n))
		var y := y0 + int((y1 - y0) * q / float(n))
		var d: int = sim.veg_d(x, y)
		var pb := to_px(x, y)
		if prev > 0:
			_dl(pa, pb, Color(COL_WOODS, 0.45 + 0.18 * prev), lw * (1.5 + 0.5 * prev))
		if (d > 0) != (prev > 0):
			draw_circle(pb, maxf(lw * 2.8, px_per_m * 0.75), Color(0, 0, 0, 0.5))
			draw_circle(pb, maxf(lw * 2.2, px_per_m * 0.6), COL_WOODS)
		prev = d
		pa = pb


func _draw_withdraw(u: int, from: Vector2, col: Color, w: float) -> void:
	var edge: float = (sim.field_h if sim.u_side[u] == 0 else 0) * px_per_m / M
	var to := Vector2(from.x, edge)
	_dd(from, to, col, w, 10.0 / zoom)
	var dir := signf(to.y - from.y)
	var s := 12.0 / zoom
	draw_line(to, to + Vector2(-s, -dir * s), col, w * 1.5)
	draw_line(to, to + Vector2(s, -dir * s), col, w * 1.5)
	_dstr(from + Vector2(s, dir * s * 2.0), "WITHDRAW",
		HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size(12.0), col)


func _draw_preview(lw: float) -> void:
	var col := Color(1, 1, 1, 0.9) if preview_ok else Color(1, 1, 1, 0.4)
	_dl(preview_a, preview_b, Color(0, 0, 0, 0.35), lw * 3.5)
	_dl(preview_a, preview_b, col, lw * 1.5)
	# End caps: hollow while the line can grow, solid once it is one rank
	# long (it stops following the finger there).
	var cap := maxf(px_per_m * 0.6, 5.0 / zoom)
	for e in [preview_a, preview_b]:
		if preview_clamped:
			draw_circle(e, cap, Color(1, 0.85, 0.35, 0.95))
		else:
			draw_arc(e, cap, 0, TAU, 14, col, lw)
	if preview_clamped:
		_dstr(preview_b + Vector2(cap * 1.5, -cap), "ONE RANK",
			HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size(12.0), Color(1, 0.85, 0.35))
	if not preview_ok or selected_units.is_empty():
		return
	var dot_r := maxf(1.5, px_per_m * 0.25)
	for p in preview_group():
		var u: int = p["unit"]
		var face: int = p["facing"]
		var centre: Vector2 = p["centre"]
		if sim.city_on != 0 and orders != null:
			# Onto (or off) a wall: the wall line and the stair, as the sim will do it.
			var c := centre / px_per_m * M
			var wpl: Dictionary = orders.wall_plan_for(u, BattleSim.make_move_order(0, u, int(c.x), int(c.y),
				face, p["width"], 0))
			if not wpl.is_empty() and wpl["mode"] != "hold":
				_draw_wall_plan(u, wpl, lw, true)
				continue
		var no_way := false
		var c2 := centre / px_per_m * M
		var pmo := BattleSim.make_move_order(0, u, int(c2.x), int(c2.y), face, p["width"], 0)
		if append_on and orders != null:
			pmo["append"] = 1
			if sim.city_on == 0 or orders.move_route_for(u, pmo).is_empty():
				# A waypoint: from the end of its chain.
				var ce: Vector3i = orders.chain_end(u)
				_dash_outlined(to_px(ce.x, ce.y), centre, Color(COL_ROUTE, 0.8), lw, 8.0 / zoom)
		if sim.city_on != 0 and orders != null:
			# The streets it will take (the sim's own search), dotted; none: red.
			var rt: Dictionary = orders.move_route_for(u, pmo)
			if not rt.is_empty():
				no_way = rt["blocked"]
				_draw_route(rt["pts"], COL_NOWAY if no_way else COL_ROUTE, lw, false)
				if no_way:
					_dstr(centre + Vector2(px_per_m * 1.5, -px_per_m * 2.0), "No way through",
						HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size(13.0), COL_NOWAY)
		var pfiles: int = p["files"]
		if sim.u_carry[u] >= 0 and BattleSim.carry_files(sim, u, sim.u_carry[u]) > 0:
			pfiles = BattleSim.carry_files(sim, u, sim.u_carry[u])  # (carrying: the ghost of its carry pattern)
		var offs := BattleSim.formation_offsets(sim.u_alive[u], pfiles, face, sim.u_type[u])
		var feat: bool = sim.map_on != 0
		for k in range(0, offs.size(), 2):
			var dp := centre + Vector2(offs[k], offs[k + 1]) * (px_per_m / M)
			var dc := Color(1, 1, 1, 0.55)
			if no_way:
				dc = COL_NOWAY
			elif feat:
				# Men who would stand in woods (green) or in a wall / house (red).
				var sx := int(dp.x / px_per_m * M)
				var sy := int(dp.y / px_per_m * M)
				if sim.obs_on != 0 and (sim.nav_at(sx, sy) & 1) == 0:
					dc = COL_BLOCK_CELL
				elif sim.veg_d(sx, sy) > 0:
					dc = Color(COL_WOODS, 0.8)
			draw_circle(dp, dot_r, dc)
		if sim.u_wall[u] > 0:
			_dstr(centre + Vector2(0, -px_per_m * 4.0), "holds its stretch of wall",
				HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size(12.0), Color(1, 0.9, 0.6))
		var ang := face * TAU / 1024.0
		var fwd := Vector2(cos(ang), sin(ang))
		draw_line(centre, centre + fwd * px_per_m * 5.0, Color(1, 1, 0.6, 0.9), lw * 1.5)
		if feat and not no_way:
			_draw_dest_cover(u, centre, face, pfiles)


## The cover at an order's destination (2026-11-06, cover like Company of Heroes): a small shield beside the front's
## right end, green for heavy cover (a house, a wall, a tall rock between the men and the way they face), yellow for
## light (woods, hedges, a low rock, rubble), none in the open (BattleSim.cover_rating_front: directional, the same
## evaluation as the AI's cover spots).
func _draw_dest_cover(u: int, centre: Vector2, face: int, files: int) -> void:
	var c := centre / px_per_m * M
	var hw := maxi(files - 1, 0) * UT.stat(sim.u_type[u], "file_sp") / 2
	var cr: int = sim.cover_rating_front(int(c.x), int(c.y), face, hw, sim.cover_who(u))
	if cr <= 0:
		return
	var ang := face * TAU / 1024.0
	var right := Vector2(-sin(ang), cos(ang))
	var sz := maxf(px_per_m * 2.2, 12.0 / zoom)
	var at := centre + right * (hw * px_per_m / M + sz * 1.2)
	var col := Color(0.45, 0.95, 0.4, 0.95) if cr == 2 else Color(1.0, 0.85, 0.3, 0.95)
	draw_circle(at, sz * 0.75, Color(0, 0, 0, 0.45))
	UIIcons.draw_icon(self, "stance_default", Rect2(at - Vector2(sz, sz) * 0.5, Vector2(sz, sz)), col)


## Waypoints (docs/DESIGN.md "Waypoints"): unit u's chain (OrderPreview.chain)
## as numbered dots at its stops joined by the legs it will walk (the street
## search's routes in towns, dotted; red where there is no way), the ghost
## footprint at the last stop. Faint: it stays up while the unit is selected.
func _draw_chain(u: int, ch: Array, lw: float, primary: bool) -> void:
	var a := 0.75 if primary else 0.5
	for i in range(1, ch.size()):
		var lg: Dictionary = ch[i]
		var col := COL_NOWAY if lg["blocked"] else Color(COL_CHAIN, a)
		var pts: PackedInt32Array = lg["pts"]
		if pts.size() > 4 or lg["blocked"]:
			_draw_route(pts, col, lw * 0.8, false)
		elif pts.size() == 4:
			_dash_outlined(to_px(pts[0], pts[1]), to_px(pts[2], pts[3]), col, lw, 8.0 / zoom)
	var last: Dictionary = ch.back()
	if int(last["attack"]) >= 0 and ch.size() > 1:
		last = ch[ch.size() - 2]   # (the footprint is where the men stand before the attack)
	_draw_footprint(u, to_px((last["at"] as Vector2i).x, (last["at"] as Vector2i).y), int(last["face"]),
		mini(int(last["files"]), sim.u_alive[u]), sim.u_alive[u], Color(COL_CHAIN, a), Color(COL_CHAIN, 0.1), lw)
	var dr := chain_dot_r()
	var fs := _font_size(11.0)
	for i in ch.size():
		var at: Vector2i = (ch[i] as Dictionary)["at"]
		var c := to_px(at.x, at.y)
		var ring := Color(1.0, 0.85, 0.35, 0.95) if int((ch[i] as Dictionary)["run"]) != 0 else Color(COL_CHAIN, 0.95)
		draw_circle(c, dr * 1.25, Color(0, 0, 0, 0.55))
		draw_circle(c, dr, Color(0.08, 0.14, 0.08, 0.85))
		if int((ch[i] as Dictionary)["attack"]) >= 0:
			# The attack as the last point: crossed swords in a red ring, on the enemy.
			var rr := Color(1.0, 0.4, 0.3, 0.98)
			_da(c, dr, 0, TAU, 18, rr, lw * 1.3)
			var q := dr * 0.55
			draw_line(c + Vector2(-q, -q), c + Vector2(q, q), Color(1, 0.92, 0.85), lw * 1.6)
			draw_line(c + Vector2(-q, q), c + Vector2(q, -q), Color(1, 0.92, 0.85), lw * 1.6)
			draw_line(c + Vector2(-q * 1.2, q * 0.5), c + Vector2(-q * 0.5, q * 1.2), rr, lw * 1.4)
			draw_line(c + Vector2(q * 1.2, q * 0.5), c + Vector2(q * 0.5, q * 1.2), rr, lw * 1.4)
			continue
		_da(c, dr, 0, TAU, 18, ring, lw)
		var txt := str(i + 1)
		var tw := ThemeDB.fallback_font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		_dstr(c + Vector2(-tw * 0.5, fs * 0.35), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 0.9))


## Radius (world px) of a waypoint dot at the current zoom (hit tests use it).
func chain_dot_r() -> float:
	return maxf(px_per_m * 0.9, 8.0 / zoom)


## A street route (sim units, x, y pairs) as a dotted line: a dark underlay dot
## and a lit one every ~2 m, ending in a larger dot at the goal. Dots are
## screen-sized when zoomed out.
func _draw_route(pts: PackedInt32Array, col: Color, lw: float, goal_dot := true) -> void:
	if pts.size() < 4:
		return
	var step := maxf(px_per_m * 1.9, 11.0 / zoom)
	var rad := maxf(lw * 1.25, px_per_m * 0.22)
	var carry := 0.0
	var prev := to_px(pts[0], pts[1])
	var dots := 0
	for i in range(1, pts.size() / 2):
		var q := to_px(pts[i * 2], pts[i * 2 + 1])
		var seg := prev.distance_to(q)
		if seg <= 0.01:
			continue
		var dir := (q - prev) / seg
		var t := carry
		while t <= seg and dots < 600:
			var at := prev + dir * t
			draw_circle(at, rad * 1.7, Color(0, 0, 0, 0.35))
			draw_circle(at, rad, col)
			t += step
			dots += 1
		carry = t - seg
		prev = q
	if goal_dot:
		draw_circle(prev, rad * 2.4, Color(0, 0, 0, 0.4))
		draw_circle(prev, rad * 1.7, col)


## Footprint of a formation: rectangle from the front line back through the
## last rank, at the real frontage and rank count, plus a facing tick.
func _draw_footprint(u: int, front: Vector2, face: int, files: int, alive: int, edge: Color,
		fill: Color, w: float) -> void:
	var ty: int = sim.u_type[u]
	files = clampi(files, 1, maxi(alive, 1))
	var ranks := (alive + files - 1) / files
	var ang := face * TAU / 1024.0
	var fwd := Vector2(cos(ang), sin(ang))
	var right := Vector2(-fwd.y, fwd.x)
	var k := px_per_m / M
	var hw := (files - 1) * UT.stat(ty, "file_sp") * 0.5 * k + px_per_m * 0.45
	var depth := (ranks - 1) * UT.stat(ty, "rank_sp") * k + px_per_m * 0.45
	var a := front - right * hw + fwd * px_per_m * 0.45
	var b := front + right * hw + fwd * px_per_m * 0.45
	var c := b - fwd * (depth + px_per_m * 0.45)
	var d := a - fwd * (depth + px_per_m * 0.45)
	if fill.a > 0.0:
		draw_colored_polygon(PackedVector2Array([a, b, c, d]), fill)
	_dp(PackedVector2Array([b, c, d, a]), Color(edge, edge.a * 0.6), w)
	_dl(a, b, edge, w * 1.6)  # front rank, stronger
	draw_line(front, front + fwd * px_per_m * 2.5, edge, w)


## Every friendly unit's order at once (toggle in the HUD). Thin and faint so
## 20 units stay readable on a phone; selected units are skipped here and
## drawn on top by the normal selection code.
func _draw_all_orders() -> void:
	var w := 1.2 / zoom
	var col_move := Color(0.65, 1.0, 0.65, 0.55)
	var fill_move := Color(0.65, 1.0, 0.65, 0.08)
	var col_still := Color(1, 1, 1, 0.35)
	var col_attack := Color(1.0, 0.45, 0.35, 0.45)
	for u in sim.n_units:
		if selected_units.has(u) or sim.u_side[u] != player_side or sim.u_state[u] != BattleSim.U_READY:
			continue
		var alive: int = sim.u_alive[u]
		var anchor := to_px(_v(u, "ax"), _v(u, "ay"))
		var order: int = _v(u, "order")
		if order == BattleSim.O_MOVE:
			var dest := to_px(_v(u, "dx"), _v(u, "dy"))
			_dl(to_px(sim.u_cx[u], sim.u_cy[u]), dest, Color(col_move, 0.3), w)
			_draw_footprint(u, dest, _v(u, "dface"), _fv(u), alive, col_move, fill_move, w)
		elif order == BattleSim.O_ATTACK and _v(u, "target") >= 0:
			var t: int = _v(u, "target")
			if not (sim.u_ammo[u] > 0 and _draw_blocked(u, t, w)):
				_dd(anchor, to_px(sim.u_cx[t], sim.u_cy[t]), col_attack, w, 6.0 / zoom)
			_draw_footprint(u, anchor, _v(u, "face"), _fv(u), alive, Color(col_attack, 0.3), Color(0, 0, 0, 0), w)
		elif order == BattleSim.O_WITHDRAW:
			_draw_withdraw(u, anchor, Color(COL_WITHDRAW, 0.5), w)
		else:
			_draw_footprint(u, anchor, _v(u, "face"), _fv(u), alive, col_still, Color(0, 0, 0, 0), w)
		var ucls := UT.cls(sim.u_type[u])
		if ucls == UT.CLS_MISSILE or ucls == UT.CLS_ART:
			_draw_fire_line(u, w)
			if _v(u, "fire") == 0 and sim.u_ammo[u] > 0:
				_dstr(to_px(sim.u_cx[u], sim.u_cy[u]) + Vector2(10, 18) / zoom,
					"HOLD FIRE", HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size(11.0), Color(1, 0.85, 0.5, 0.8))
			if ucls == UT.CLS_ART and (_v(u, "refill") != 0 or sim.u_rprog[u] > 0):
				var full_ammo: int = sim.u_neng[u] * UT.stat(sim.u_type[u], "m_ammo")
				_dstr(to_px(sim.u_cx[u], sim.u_cy[u]) + Vector2(10, 46) / zoom,
					"REFILLING %d%%" % (maxi(sim.u_ammo[u], 0) * 100 / maxi(full_ammo, 1)),
					HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size(11.0), Color(0.55, 0.85, 1.0, 0.9))
			if ucls == UT.CLS_ART and _v(u, "deploy") == 0:
				_dstr(to_px(sim.u_cx[u], sim.u_cy[u]) + Vector2(10, 32) / zoom,
					"PACKED UP", HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size(11.0), Color(0.85, 0.9, 1.0, 0.8))


## Formations implied by the current preview line. The line is the front
## rank: it faces 90 degrees anticlockwise (on screen) from the drag
## direction, so a left-to-right drag faces up the screen. One unit takes
## the whole line; a group is laid out side by side along it, keeping the
## units' current left-to-right order, each getting frontage in proportion to
## its soldiers. Entries: {unit, centre (world px), facing, width, files}.
func preview_group() -> Array:
	var out: Array = []
	var d := preview_b - preview_a
	var len_px := d.length()
	if len_px <= 0.0:
		return out
	var dir := d / len_px
	var face_ang := atan2(d.y, d.x) - PI * 0.5
	var face := int(round(face_ang * 1024.0 / TAU)) & 1023
	var units: Array[int] = []
	for u in selected_units:
		if sim.u_state[u] == BattleSim.U_READY:
			units.append(u)
	if units.is_empty():
		return out
	# Left-to-right along the drag direction, by current position.
	units.sort_custom(func(a: int, b: int) -> bool:
		var pa := to_px(sim.u_cx[a], sim.u_cy[a]).dot(dir)
		var pb := to_px(sim.u_cx[b], sim.u_cy[b]).dot(dir)
		return pa < pb or (pa == pb and a < b))
	var len_m := len_px / px_per_m
	var gaps := GROUP_GAP_M * (units.size() - 1)
	var usable := maxf(len_m - gaps, 1.0)
	var total_w := 0.0
	for u in units:
		total_w += _line_weight(u)
	var x := 0.0
	for u in units:
		var share: float = usable * _line_weight(u) / total_w
		if units.size() == 1:
			share = len_m
		var width := int(share * M)
		var files: int = BattleSim.width_to_files(width, sim.u_alive[u], sim.u_type[u])
		if sim.u_neng[u] > 0:
			files = sim.u_neng[u]  # a battery's frontage is its engines
		var centre: Vector2 = preview_a + dir * (x + share * 0.5) * px_per_m
		if units.size() == 1:
			centre = (preview_a + preview_b) * 0.5
		out.append({"unit": u, "centre": centre, "facing": face, "width": width, "files": files})
		x += share + GROUP_GAP_M
	return out


## Share of a drawn line a unit gets: its soldiers' file width (a battery:
## its engines' frontage, weighted like a four-rank unit).
func _line_weight(u: int) -> float:
	var fsp := float(UT.stat(sim.u_type[u], "file_sp"))
	if sim.u_neng[u] > 0:
		return sim.u_neng[u] * fsp * 4.0
	return sim.u_alive[u] * fsp


## Single-unit form of preview_group (kept for callers and tests).
func preview_formation() -> Dictionary:
	var g := preview_group()
	if g.is_empty():
		return {"centre": (preview_a + preview_b) * 0.5, "facing": 0, "width": 0, "files": 1}
	return g[0]


## The longest line the selection can be drawn along: every unit in one
## rank (men alive x file spacing; a battery its engines), plus the gaps
## between them (world px).
func max_line_px() -> float:
	var total := 0.0
	var n := 0
	for u in selected_units:
		if sim.u_state[u] != BattleSim.U_READY:
			continue
		var fsp := float(UT.stat(sim.u_type[u], "file_sp"))
		total += (sim.u_neng[u] if sim.u_neng[u] > 0 else sim.u_alive[u]) * fsp / M
		n += 1
	return (total + GROUP_GAP_M * maxi(n - 1, 0)) * px_per_m


# ---------------------------------------------------------------- walls ---

## A wall stretch highlighted (its walkway, from end to end).
func _draw_stretch(sg: int, lw: float, a: float) -> void:
	var p0 := to_px(sim.ws_x0[sg], sim.ws_y0[sg])
	var p1 := to_px(sim.ws_x1[sg], sim.ws_y1[sg])
	_dl(p0, p1, Color(COL_WALL, a * 0.5), maxf(px_per_m * 4.0, lw * 3.0))
	_dl(p0, p1, Color(COL_WALL, a), lw)


## Mouse over a wall with a unit selected that may man it: its stretch.
func _draw_wall_hover(w: Vector2, lw: float) -> void:
	if sim.city_on == 0 or sim.ws_x0.size() == 0:
		return
	var any := false
	for u in selected_units:
		if BattleSim.can_man_walls(sim, u) or sim.u_wall[u] > 0:
			any = true
	if not any:
		return
	var ws := BattleSim.wall_snap(sim, int(w.x / px_per_m * M), int(w.y / px_per_m * M))
	if ws.z >= 0:
		_draw_stretch(ws.z, lw, 0.55)


## A unit's wall move (OrderPreview.plan_from): the stretch it takes and
## its men in their wall line there, the stair it uses (ringed) and its way
## to it (dashed), and a caption.
func _draw_wall_plan(u: int, wp: Dictionary, lw: float, primary: bool) -> void:
	var sg: int = wp["seg"]
	var slots: PackedInt32Array = wp["slots"]
	if sg >= 0:
		_draw_stretch(sg, lw, 0.75 if wp["mode"] != "hold" else 0.35)
		var seen := {sg: true}
		for k in range(0, slots.size(), 2):
			var s2: int = sim.walk_seg_at(slots[k], slots[k + 1])
			if s2 >= 0 and not seen.has(s2):
				seen[s2] = true
				_draw_stretch(s2, lw, 0.6)  # the line goes on through a tower onto it
	var dot := maxf(1.2, px_per_m * 0.3)
	for k in range(0, slots.size(), 2):
		draw_circle(to_px(slots[k], slots[k + 1]), dot, Color(1, 1, 0.75, 0.85))
	var route: PackedInt32Array = wp["route"]
	if route.size() >= 4:
		var pts := PackedVector2Array()
		for k in range(0, route.size(), 2):
			pts.append(to_px(route[k], route[k + 1]))
		for k in pts.size() - 1:
			_dash_outlined(pts[k], pts[k + 1], Color(COL_STAIR, 0.9), lw, 8.0 / zoom)
	var ss: int = wp["stair_seg"]
	if ss >= 0:
		var e: int = wp["stair_end"]
		var sp := to_px(sim.stair_pt(ss, e, 1).x, sim.stair_pt(ss, e, 1).y)
		var rr := maxf(px_per_m * 3.0, 9.0 / zoom)
		draw_circle(sp, rr, Color(COL_STAIR, 0.22))
		draw_arc(sp, rr, 0, TAU, 20, COL_STAIR, lw * 1.4)
		if wp.has("up_seg"):
			var e2: int = wp["up_end"]
			var s2p := to_px(sim.stair_pt(wp["up_seg"], e2, 1).x, sim.stair_pt(wp["up_seg"], e2, 1).y)
			draw_circle(s2p, rr, Color(COL_STAIR, 0.22))
			draw_arc(s2p, rr, 0, TAU, 20, COL_STAIR, lw * 1.4)
		if primary:
			_dstr(sp + Vector2(rr * 1.2, -rr * 0.3), "STAIR",
				HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size(12.0), COL_STAIR)
	if wp.has("foot"):
		# Ladders against the wall at the foot: two rails and rungs.
		var fp: Vector2i = wp["foot"]
		var fpx := to_px(fp.x, fp.y)
		var dir: float = sim.ws_dir[int(wp["seg"])] * TAU / 1024.0
		var inw := -Vector2(cos(dir), sin(dir)) * px_per_m * 3.0
		var side := Vector2(-sin(dir), cos(dir)) * px_per_m * 0.5
		for rail in [-1.0, 1.0]:
			draw_line(fpx + side * rail, fpx + side * rail + inw, Color(COL_STAIR, 0.95), lw * 1.2)
		for k in 4:
			var q := fpx + inw * (0.2 + 0.2 * k)
			draw_line(q - side, q + side, Color(COL_STAIR, 0.95), lw)
	if primary and wp["mode"] != "hold":
		var txt: String = {"up": "UP BY THE STAIR", "down": "DOWN BY THE STAIR", "along": "ALONG THE WALL",
			"ladder": "UP BY LADDERS"}.get(wp["mode"], "")
		var tower_mv: bool = wp["mode"] == "ladder" and bool(wp.get("tower", false))
		if tower_mv:
			txt = "ACROSS THE SIEGE TOWER"
		if wp["mode"] == "ladder" and bool(wp.get("plant", false)):
			txt = "PLANT THE SIEGE TOWER HERE" if tower_mv else "PLANT LADDERS HERE"
		if wp["mode"] == "climb":
			var up := 0
			var base: int = sim.u_slot_base[u]
			for k in sim.u_alive[u]:
				var i: int = sim.slot_soldier[base + k]
				if sim._on_walk(sim.pos_x[i], sim.pos_y[i]):
					up += 1
			txt = ("CROSSING: %d OF %d OVER" if bool(wp.get("tower", false)) else "CLIMBING: %d OF %d UP") % [up, sim.u_alive[u]]
		if wp["mode"] == "down" and sg >= 0:
			txt = "DOWN, THEN UP ONTO THAT WALL"
		var at := to_px(sim.u_cx[u], sim.u_cy[u])
		if sg >= 0 and slots.size() >= 2:
			at = to_px(slots[0], slots[1])
		_dstr(at + Vector2(0, -px_per_m * 4.0), txt,
			HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size(13.0), COL_WALL)


## Engines left on the field (abandoned, neutral; any foot can take them
## up): a grey marker with the engine's symbol over their middle and a
## dashed ring round them.
func _draw_free_engines(r: float, lw: float) -> void:
	for g in sim.n_eg:
		if not sim.engines_free(g) or UT.stat(sim.eg_type[g], "fixed") != 0:
			continue
		var whole := false
		for k in sim.eg_ne[g]:
			if sim.e_state[sim.eg_e0[g] + k] != BattleSim.E_WRECKED:
				whole = true
		if not whole:
			continue
		var at: Vector2i = BattleSim.engines_at(sim, g)
		var c := to_px(at.x, at.y)
		var rad: float = ((int(sim.eg_ne[g]) - 1) * UT.stat(sim.eg_type[g], "file_sp") / 2.0 / 1024.0 + 4.0) * px_per_m
		var col := Color(0.85, 0.85, 0.8, 0.8)
		for k in 16:
			var a0 := TAU * k / 16.0
			draw_arc(c, rad, a0, a0 + TAU / 32.0, 3, col, lw)
		_up(c)
		Icons.draw_marker(self, Icons.icon_of(sim.eg_type[g]), c + Vector2(0, -marker_dy(r)), r * 0.85,
			Color(0.55, 0.55, 0.52), Color.WHITE)
		_flat()


## A siege tower (view only): a tall box seen from above (the storeys as
## inset squares), its ramp toward the way it faces (carried: its carriers'
## front; planted: over the wall's walkway, the ramp down); wrecked, a dark
## frame with a cross.
func _draw_siege_tower(q: int, c: Vector2, fwd: Vector2, side: Vector2, st: int, lw: float) -> void:
	var dark := Color(0.2, 0.12, 0.05, 0.95)
	var h := float(BattleSim.EQ_DEPTH2[sim.q_kind[q]]) / 1024.0  # half its side, m
	if st == BattleSim.Q_PLANTED:
		var dir: float = sim.ws_dir[sim.q_seg[q]] * TAU / 1024.0
		var qc: Vector2i = sim.eq_centre(q)
		c = to_px(qc.x, qc.y)
		fwd = -Vector2(cos(dir), sin(dir)) * px_per_m  # toward the wall
		side = Vector2(-fwd.y, fwd.x)
	elif st == BattleSim.Q_CARRIED:
		c += fwd * 1.0  # (pushed ahead of its men)
	var wrecked := st == BattleSim.Q_WRECKED
	var body := Color(0.5, 0.34, 0.18, 0.95) if not wrecked else Color(0.25, 0.2, 0.15, 0.7)
	var pts := PackedVector2Array([c + fwd * h + side * h, c + fwd * h - side * h,
		c - fwd * h - side * h, c - fwd * h + side * h])
	draw_colored_polygon(pts, body)
	pts.append(pts[0])
	draw_polyline(pts, dark, lw * 1.5)
	if wrecked:
		draw_line(pts[0], pts[2], dark, lw * 1.5)
		draw_line(pts[1], pts[3], dark, lw * 1.5)
		return
	for k in [0.65, 0.3]:
		var ins := PackedVector2Array([c + (fwd + side) * h * k, c + (fwd - side) * h * k,
			c - (fwd + side) * h * k, c - (fwd - side) * h * k])
		ins.append(ins[0])
		draw_polyline(ins, Color(0.32, 0.2, 0.1, 0.9), lw)
	# The ramp (the drawbridge): down onto the walkway when planted, raised
	# (a short flap) while it moves.
	var rl := 3.5 if st == BattleSim.Q_PLANTED else 1.0
	var r0 := c + fwd * h
	var ramp := PackedVector2Array([r0 + side * h * 0.7, r0 - side * h * 0.7,
		r0 + fwd * rl - side * h * 0.7, r0 + fwd * rl + side * h * 0.7])
	draw_colored_polygon(ramp, Color(0.62, 0.45, 0.25, 0.95))
	for k in 4:
		var rq := r0 + fwd * rl * (0.2 + 0.2 * k)
		draw_line(rq - side * h * 0.7, rq + side * h * 0.7, dark, lw * 0.6)


## A mantlet (view only), seen from above: a thick short bar of planks
## its panel line's length (q_len) across the way it faces, a lighter plank face on its
## front, two posts behind; carried, at its carriers' front along their
## facing; wrecked, charred with a cross. (Fire: _draw_fires.)
func _draw_mantlet(q: int, c: Vector2, fwd: Vector2, st: int, lw: float) -> void:
	if st != BattleSim.Q_CARRIED:
		var a: float = sim.q_face[q] * TAU / 1024.0
		fwd = Vector2(cos(a), sin(a)) * px_per_m
	else:
		c += fwd * 0.8  # (held up before the front rank)
	var side := Vector2(-fwd.y, fwd.x)
	var ln: int = sim.q_len[q] if sim.q_len[q] > 0 else BattleSim.EQ_SCREEN_W[sim.q_kind[q]]
	var hw := float(ln) / 1024.0 / 2.0  # half its panel line's length, m
	var wrecked := st == BattleSim.Q_WRECKED
	var dark := Color(0.2, 0.12, 0.05, 0.95)
	var body := Color(0.45, 0.3, 0.15, 0.95) if not wrecked else Color(0.18, 0.15, 0.12, 0.8)
	var pts := PackedVector2Array([c + fwd * 0.3 + side * hw, c + fwd * 0.3 - side * hw,
		c - fwd * 0.3 - side * hw, c - fwd * 0.3 + side * hw])
	draw_colored_polygon(pts, body)
	pts.append(pts[0])
	draw_polyline(pts, dark, lw)
	if wrecked:
		draw_line(pts[0], pts[2], dark, lw * 1.5)
		draw_line(pts[1], pts[3], dark, lw * 1.5)
		return
	draw_line(c + fwd * 0.3 + side * hw * 0.95, c + fwd * 0.3 - side * hw * 0.95, Color(0.75, 0.58, 0.35, 1.0), lw * 1.5)
	for sg in [-1.0, 1.0]:
		var pp: Vector2 = c - fwd * 0.6 + side * hw * 0.7 * sg
		draw_circle(pp, maxf(px_per_m * 0.25, lw), dark)


## Mantlet cover hints for selected unit u: carrying one, where its cover
## would be if put down now (its frontage long, EQ_SCREEN_D deep behind its
## front); and (primary only) the cover behind its side's standing mantlets.
func _draw_mantlet_cover(u: int, lw: float, primary: bool) -> void:
	if sim.mt_on == 0:
		return
	var col := Color(0.55, 0.85, 1.0, 0.5)
	var fill := Color(0.55, 0.85, 1.0, 0.08)
	var cq: int = sim.u_carry[u]
	if cq >= 0 and BattleSim.EQ_SCREEN[sim.q_kind[cq]] != 0:
		_cover_rect(to_px(sim.u_ax[u], sim.u_ay[u]), sim.u_face[u], BattleSim.mantlet_len(sim, u),
			BattleSim.EQ_SCREEN_D[sim.q_kind[cq]], col, fill, lw)
	if not primary:
		return
	for q in sim.n_eq:
		var k: int = sim.q_kind[q]
		if BattleSim.EQ_SCREEN[k] == 0 or sim.q_state[q] != BattleSim.Q_GROUND or sim.q_side[q] != sim.u_side[u]:
			continue
		var ln: int = sim.q_len[q] if sim.q_len[q] > 0 else BattleSim.EQ_SCREEN_W[k]
		_cover_rect(to_px(sim.q_x[q], sim.q_y[q]), sim.q_face[q], ln, BattleSim.EQ_SCREEN_D[k],
			Color(col, 0.35), fill, lw)


## A dashed cover rectangle: `ln` along a line through `front` across
## `face`, `depth` behind it (sim units).
func _cover_rect(front: Vector2, face: int, ln: int, depth: int, col: Color, fill: Color, lw: float) -> void:
	var ang := face * TAU / 1024.0
	var fwd := Vector2(cos(ang), sin(ang))
	var right := Vector2(-fwd.y, fwd.x)
	var hl := ln * px_per_m / M / 2.0
	var dp := depth * px_per_m / M
	var pts := PackedVector2Array([front - right * hl, front + right * hl,
		front + right * hl - fwd * dp, front - right * hl - fwd * dp])
	draw_colored_polygon(pts, fill)
	pts.append(pts[0])
	for k in 4:
		_dd(pts[k], pts[k + 1], col, lw, 5.0 / zoom)


## Siege towers on the ground (anyone's for the taking, the enemy's too): a
## marker with the siege tower's symbol over it and a dashed ring round it,
## as for engines left on the field.
func _draw_free_towers(r: float, lw: float) -> void:
	for q in sim.n_eq:
		if sim.q_state[q] != BattleSim.Q_GROUND or BattleSim.EQ_EXPOSED[sim.q_kind[q]] == 0:
			continue
		var c := to_px(sim.q_x[q], sim.q_y[q])
		var rad := (float(BattleSim.EQ_DEPTH2[sim.q_kind[q]]) / 1024.0 + 2.5) * px_per_m
		var col := Color(0.85, 0.85, 0.8, 0.8)
		for k in 16:
			var a0 := TAU * k / 16.0
			draw_arc(c, rad, a0, a0 + TAU / 32.0, 3, col, lw)
		var mc := c + Vector2(0, -marker_dy(r))
		_up(c)
		draw_circle(mc, r * 0.85, Color(0.55, 0.55, 0.52))
		draw_arc(mc, r * 0.85, 0.0, TAU, 24, Color.WHITE, lw)
		UIIcons.draw_icon(self, "siege_tower", Rect2(mc - Vector2(r, r) * 0.7, Vector2(r, r) * 1.4), Color.WHITE)
		_flat()


## Siege gear (view only): the attackers' ladder sets and rams, on the
## ground, carried (at the carriers' front, along their facing) or planted
## against a wall (five ladders, rails and rungs); a wrecked ram as wreckage.
## An ammunition wagon: a covered box on two wheels with its team in front
## (horses alive: dots; shot down: crosses), wrecked as a dark cross; the
## stock left as a bar under it (standard kinds, all together).
func _draw_wagon(q: int, c: Vector2, fwd: Vector2, side: Vector2, st: int, lw: float) -> void:
	var dark := Color(0.2, 0.12, 0.05, 0.95)
	var wrecked := st == BattleSim.Q_WRECKED
	if _props_tex != null:
		if not wrecked:
			_draw_wagon_stock(q, c, lw)
		return  # (the sprite: _draw_props)
	var body := Color(0.62, 0.5, 0.32, 0.95) if not wrecked else Color(0.25, 0.2, 0.15, 0.7)
	var pts := PackedVector2Array([c + fwd * 2.2 + side * 1.1, c + fwd * 2.2 - side * 1.1,
		c - fwd * 2.2 - side * 1.1, c - fwd * 2.2 + side * 1.1])
	draw_colored_polygon(pts, body)
	pts.append(pts[0])
	draw_polyline(pts, dark, lw)
	for sg in [-1.0, 1.0]:
		draw_line(c + side * 1.3 * sg - fwd * 0.9, c + side * 1.3 * sg + fwd * 0.9, dark, lw * 2.0)
	if wrecked:
		draw_line(pts[0], pts[2], dark, lw * 1.5)
		draw_line(pts[1], pts[3], dark, lw * 1.5)
		return
	var tier: int = sim.q_tier[q]
	var horses := UT.wagon_stat(tier, "horses")
	for h in horses:
		var hp := c + fwd * 3.8 + side * (0.0 if horses == 1 else (h - 0.5) * 1.6)
		if h < int(sim.q_hn[q]):
			draw_circle(hp, maxf(px_per_m * 0.6, lw * 2.0), Color(0.42, 0.3, 0.2, 0.95))
		else:
			draw_line(hp - side * 0.5 - fwd * 0.5, hp + side * 0.5 + fwd * 0.5, dark, lw)
			draw_line(hp + side * 0.5 - fwd * 0.5, hp - side * 0.5 + fwd * 0.5, dark, lw)
	_draw_wagon_stock(q, c, lw)


## The wagon's stock left, a bar under it.
func _draw_wagon_stock(q: int, c: Vector2, lw: float) -> void:
	var tier: int = sim.q_tier[q]
	var left := 0
	var full := 0
	for k in UT.AMMO.size():
		if UT.ammo_stat(k, "base") < 0:
			left += sim.wagon_stock(q, k) * 100 / maxi(UT.ammo_stat(k, "wagon"), 1)
			full += UT.wagon_stat(tier, "stock_pct")
	if full > 0:
		var bw := px_per_m * 4.0
		var at := c + Vector2(-bw * 0.5, px_per_m * 2.6)
		draw_rect(Rect2(at, Vector2(bw, maxf(px_per_m * 0.4, lw))), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(at, Vector2(bw * clampf(float(left) / full, 0.0, 1.0), maxf(px_per_m * 0.4, lw))),
			Color(0.95, 0.8, 0.35, 0.95))


## Burning things (gates, engines, equipment): a flicker of flame over each.
func _draw_fires(lw: float) -> void:
	var t := Time.get_ticks_msec() / 160.0
	var pts: Array[Vector2] = []
	for g in sim.n_gates:
		if sim.g_burn[g] > 0:
			pts.append(to_px(sim.g_x[g], sim.g_y[g]))
	for e in sim.n_eng:
		if sim.e_burn[e] > 0:
			pts.append(to_px(sim.e_x[e], sim.e_y[e]))
	for q in sim.n_eq:
		if sim.q_burn[q] > 0:
			var qc: Vector2i = sim.eq_centre(q)
			pts.append(to_px(qc.x, qc.y))
	for k in pts.size():
		var p: Vector2 = pts[k]
		_up(p)
		var f := 0.75 + 0.25 * sin(t + k * 1.7)
		var h := maxf(px_per_m * 3.0, 14.0 / zoom) * f
		var w := h * 0.45
		draw_colored_polygon(PackedVector2Array([p + Vector2(-w, 0), p + Vector2(0, -h), p + Vector2(w, 0)]),
			Color(1.0, 0.45, 0.1, 0.85))
		draw_colored_polygon(PackedVector2Array([p + Vector2(-w * 0.5, 0), p + Vector2(0, -h * 0.6),
			p + Vector2(w * 0.5, 0)]), Color(1.0, 0.85, 0.3, 0.9))
		draw_line(p + Vector2(-w, 0), p + Vector2(w, 0), Color(0.3, 0.1, 0.0, 0.8), lw)
		_smoke_column(p - Vector2(0, h * 0.7), k, 4, px_per_m * 9.0, px_per_m * 1.5, 0.4, _clock * 0.25 + k * 0.31)
		_flat()
	if sim.ob_fire_n > 0:
		_draw_bld_fires(lw)


## Burning buildings (sim ob_fire; fire, 2026-10-24): a few flames along the
## footprint's long axis (one a 8 m, at most three; taller as it burns
## down) and one smoke column over it, darker and wider than an engine's.
## Phone cost: a handful of polygons and four puffs a building, culled to
## the view.
func _draw_bld_fires(lw: float) -> void:
	var blds: Array = (sim.map_info.get("city", {}) as Dictionary).get("buildings", [])
	var vr := _view_rect()
	var t := Time.get_ticks_msec() / 140.0
	var pm := px_per_m
	for b in mini(sim.ob_fire.size(), blds.size()):
		if sim.ob_fire[b] == 0:
			continue
		var a: Array = blds[b]
		var x0 := float(int(a[0]))
		var y0 := float(int(a[1]))
		var x1 := float(int(a[2]))
		var y1 := float(int(a[3]))
		var c := Vector2(x0 + x1, y0 + y1) * 0.5 * pm
		if not vr.has_point(c):
			continue
		var burnt := 1.0 - clampf(float(sim.ob_hp[b]) / maxf(float(sim.ob_hp0[b]), 1.0), 0.0, 1.0)
		var along := Vector2(x1 - x0, 0.0) if x1 - x0 >= y1 - y0 else Vector2(0.0, y1 - y0)
		var n := clampi(int(along.length() / 8.0) + 1, 1, 3)
		for k in n:
			var p := c + along * pm * ((k + 0.5) / n - 0.5) * 0.7
			_up(p)
			var f := 0.7 + 0.3 * sin(t + b * 2.3 + k * 1.9)
			var h := maxf(pm * (2.2 + 2.0 * burnt), 12.0 / zoom) * f
			var w := h * 0.42
			draw_colored_polygon(PackedVector2Array([p + Vector2(-w, 0), p + Vector2(0, -h), p + Vector2(w, 0)]),
				Color(1.0, 0.42, 0.08, 0.85))
			draw_colored_polygon(PackedVector2Array([p + Vector2(-w * 0.5, 0), p + Vector2(0, -h * 0.6),
				p + Vector2(w * 0.5, 0)]), Color(1.0, 0.85, 0.3, 0.9))
			draw_line(p + Vector2(-w, 0), p + Vector2(w, 0), Color(0.3, 0.1, 0.0, 0.8), lw)
		_up(c)
		_smoke_column(c - Vector2(0, pm * 3.0), b, 4, pm * (12.0 + 6.0 * burnt), pm * (2.0 + 1.5 * burnt), 0.45,
			_clock * 0.2 + b * 0.37)
		_flat()


## Piece q's heading on screen (radians): its carriers' facing, a little
## askew lying on the ground; NAN while a reinforcement's (not on the field).
func _gear_angle(q: int) -> float:
	var st: int = sim.q_state[q]
	var u: int = sim.q_unit[q]
	if st == BattleSim.Q_CARRIED and u >= 0 and sim.u_state[u] == BattleSim.U_RESERVE:
		return NAN
	if st == BattleSim.Q_CARRIED and u >= 0:
		return sim.u_face[u] * TAU / 1024.0
	if st == BattleSim.Q_GROUND or st == BattleSim.Q_WRECKED:
		return (sim.q_x[q] / 1024 % 7) * 0.4  # lying a little askew
	return 0.0


## Wagons as sprites (the _props node's draw): the hand cart or the wagon
## (walk frames while it moves, the wreck = the death's last frame) and the
## wagon's horses ahead of it (dead ones lying, the death's last frame).
func _draw_props() -> void:
	if sim == null or _props_tex == null or BoardView.oblique:
		return  # (the oblique view stands the wagons up: siege_gear_ob.gd)
	var vr := _view_rect().grow(px_per_m * 8.0)
	for q in sim.n_eq:
		if sim.q_kind[q] != BattleSim.EQ_WAGON:
			continue
		var ang := _gear_angle(q)
		if is_nan(ang):
			continue
		var c := to_px(sim.q_x[q], sim.q_y[q])
		if not vr.has_point(c):
			continue
		var st: int = sim.q_state[q]
		var seen: Array = _q_moved.get(q, [sim.q_x[q], sim.q_y[q], -100])
		if seen[0] != sim.q_x[q] or seen[1] != sim.q_y[q]:
			seen = [sim.q_x[q], sim.q_y[q], sim.tick]
		_q_moved[q] = seen
		var moving: bool = st == BattleSim.Q_CARRIED and sim.tick - int(seen[2]) <= 2
		var tier: int = sim.q_tier[q]
		var wrecked := st == BattleSim.Q_WRECKED
		var act := 3 if wrecked else (1 if moving else 0)
		var phase := float(q) * 0.37
		_draw_prop("cart" if tier == 0 else "wagon", act, -1 if wrecked else int(_clock * 9.0 + phase * 6.0), c, ang)
		if wrecked:
			continue
		var horses := UT.wagon_stat(tier, "horses")
		var fwd := Vector2(cos(ang), sin(ang)) * px_per_m
		var side := Vector2(-fwd.y, fwd.x)
		for h in horses:
			var hp := c + fwd * 3.9 + side * (0.0 if horses == 1 else (h - 0.5) * 1.05)
			if h < int(sim.q_hn[q]):
				_draw_prop("draft_horse", 1 if moving else 0, int(_clock * 9.0 + phase * 6.0 + h * 2.0), hp, ang)
			else:
				_draw_prop("draft_horse", 3, -1, hp, ang)


## Prop `prop`'s action `act` (0 idle, 1 walk, 2 attack, 3 death) frame
## `fr` (wrapped; -1 = the last) with its anchor at c, turned by ang.
func _draw_prop(prop: String, act: int, fr: int, c: Vector2, ang: float) -> void:
	var rows: Array = SpriteAtlas.PROPS[prop]
	var a: Vector4 = rows[act * 2]
	var b: Vector4 = rows[act * 2 + 1]
	var n := int(b.w)
	var k := n - 1 if fr < 0 else posmod(fr, n)
	var sc := px_per_m / PROP_PX_PER_M
	_props.draw_set_transform(c, ang, Vector2(sc, sc))
	_props.draw_texture_rect_region(_props_tex, Rect2(-b.x, -b.y, a.z, a.w),
		Rect2(a.x + k * b.z, a.y, a.z, a.w))
	_props.draw_set_transform_matrix(Transform2D.IDENTITY)


func _draw_siege_gear(lw: float) -> void:
	if BoardView.oblique:
		_siege_ob.draw_all(self, sim, px_per_m, lw, _gear_angle)
		for q in sim.n_eq:
			if sim.q_kind[q] == BattleSim.EQ_WAGON and sim.q_state[q] != BattleSim.Q_WRECKED and not is_nan(_gear_angle(q)):
				_draw_wagon_stock(q, to_px(sim.q_x[q], sim.q_y[q]), lw)
		return
	var wood := Color(0.55, 0.38, 0.2, 1.0)
	var dark := Color(0.2, 0.12, 0.05, 0.95)
	for q in sim.n_eq:
		if BattleSim.EQ_FW[sim.q_kind[q]] != 0:
			continue  # (field works: the works layer)
		var st: int = sim.q_state[q]
		var c := to_px(sim.q_x[q], sim.q_y[q])
		var ang := _gear_angle(q)
		if is_nan(ang):
			continue  # (a reinforcement's wagon: not on the field yet)
		var fwd := Vector2(cos(ang), sin(ang)) * px_per_m
		var side := Vector2(-fwd.y, fwd.x)
		if sim.q_kind[q] == BattleSim.EQ_WAGON:
			_draw_wagon(q, c, fwd, side, st, lw)
			continue
		if BattleSim.EQ_EXPOSED[sim.q_kind[q]] != 0:
			_draw_siege_tower(q, c, fwd, side, st, lw)
			continue
		if BattleSim.EQ_SCREEN[sim.q_kind[q]] != 0:
			_draw_mantlet(q, c, fwd, st, lw)
			continue
		if sim.q_kind[q] == BattleSim.EQ_RAM:
			if st == BattleSim.Q_CARRIED:
				c -= fwd * 2.0  # (its head at the carriers' front)
			var pts := PackedVector2Array([c + fwd * 3.5 + side * 1.4, c + fwd * 3.5 - side * 1.4,
				c - fwd * 3.0 - side * 1.4, c - fwd * 3.0 + side * 1.4])
			var col := Color(0.45, 0.3, 0.16, 0.9) if st != BattleSim.Q_WRECKED else Color(0.25, 0.2, 0.15, 0.7)
			draw_colored_polygon(pts, col)
			pts.append(pts[0])
			draw_polyline(pts, dark, lw)
			if st == BattleSim.Q_WRECKED:
				draw_line(pts[0], pts[2], dark, lw * 1.5)
				draw_line(pts[1], pts[3], dark, lw * 1.5)
			else:
				draw_line(c - fwd * 3.0, c + fwd * 4.6, Color(0.3, 0.2, 0.1, 1.0), lw * 2.0)  # the beam's head
			continue
		if st == BattleSim.Q_PLANTED:
			var dir: float = sim.ws_dir[sim.q_seg[q]] * TAU / 1024.0
			var inw := -Vector2(cos(dir), sin(dir)) * px_per_m * 3.5
			var side2 := Vector2(-sin(dir), cos(dir)) * px_per_m * 0.45
			var poles: bool = sim.q_kind[q] == BattleSim.EQ_POLES
			for k in BattleSim.EQ_LANES[sim.q_kind[q]]:
				var f: Vector2i = sim.set_ladder_foot(q, k)
				var fp := to_px(f.x, f.y)
				if poles:
					# A notched scaling pole: one trunk, the notches as short ticks.
					draw_line(fp, fp + inw, wood, lw * 1.4)
					for r in 5:
						var nq := fp + inw * (0.15 + 0.18 * r)
						draw_line(nq, nq + side2 * 0.9, wood, lw * 0.7)
					continue
				for rail in [-1.0, 1.0]:
					draw_line(fp + side2 * rail, fp + side2 * rail + inw, wood, lw)
				for r in 5:
					var rq := fp + inw * (0.15 + 0.18 * r)
					draw_line(rq - side2, rq + side2, wood, lw * 0.8)
			continue
		# A bundle of five ladders (on the ground or on the carriers' shoulders).
		if st == BattleSim.Q_CARRIED:
			c -= fwd * 1.5
		if sim.q_kind[q] == BattleSim.EQ_POLES:
			# Two scaling poles, longer than the ladders, a few notches.
			for k in 2:
				var o := side * (float(k) - 0.5) * 0.6
				draw_line(c - fwd * 3.6 + o, c + fwd * 3.6 + o, wood, lw * 1.4)
			continue
		for k in 3:
			var o := side * (float(k) - 1.0) * 0.7
			draw_line(c - fwd * 3.0 + o, c + fwd * 3.0 + o, wood, lw * 1.3)
		for r in 6:
			var rq := c + fwd * (-2.6 + r * 1.04)
			draw_line(rq - side * 0.9, rq + side * 0.9, wood, lw * 0.7)


## Deployment: field works placements not applied yet, and a stakes line
## being dragged, as ghosts where the sim's placement rule (works_rule)
## will put them.
func _draw_works_pending(lw: float) -> void:
	if orders != null:
		for o in orders.pending_works():
			var od: Dictionary = (o as Dictionary).duplicate()
			if not od.has("side"):
				od["side"] = player_side
			var r: Vector4i = BattleSim.works_rule(sim, od)
			if r.x < 0:
				continue
			if int(od.get("on", 1)) == 0:
				var c0 := to_px(sim.q_x[r.x], sim.q_y[r.x])
				draw_line(c0 + Vector2(-1, -1) * px_per_m * 2.0, c0 + Vector2(1, 1) * px_per_m * 2.0, COL_BLOCKED, lw * 2.0)
				draw_line(c0 + Vector2(-1, 1) * px_per_m * 2.0, c0 + Vector2(1, -1) * px_per_m * 2.0, COL_BLOCKED, lw * 2.0)
				continue
			WorksLayer.draw_piece(self, sim, r.x, px_per_m, lw, true, to_px(r.y, r.z), r.w)
	if works_drag:
		var d := preview_b - preview_a
		_dash_outlined(preview_a, preview_b, Color(1.0, 0.85, 0.45, 0.9), lw, px_per_m * 1.5)
		if d.length() > 1.0:
			var n := Vector2(-d.y, d.x).normalized()
			if (n.y > 0.0) == (player_side == 0):
				n = -n
			var mid := (preview_a + preview_b) * 0.5
			var hl := float(BattleSim.EQ_FW_LEN[BattleSim.EQ_STAKES]) / M * px_per_m / 2.0
			var t := d.normalized()
			draw_line(mid - t * hl, mid + t * hl, Color(0.62, 0.45, 0.24, 0.9), lw * 2.0)
			draw_line(mid, mid + n * px_per_m * 3.0, Color(1.0, 0.85, 0.45, 0.9), lw)
			var fs := _font_size(13.0)
			_dstr(mid + n * px_per_m * 3.5, "STAKES FACE THIS WAY",
				HORIZONTAL_ALIGNMENT_CENTER, -1, fs, Color(1.0, 0.9, 0.6))


# ------------------------------------------------- the placement tool (view only) ---
# Confirm orders (game/confirm_orders.gd): a tap or a line drag with units selected places a ghost of the selection instead
# of ordering; game/battle.gd keeps the ghost's state and sets these fields, this draws it: the line and the men's dots as
# the drag preview does (a line ghost reuses preview_a / preview_b / _draw_preview), a cyan footprint per unit, and the
# handles upright in the oblique view like the markers (body: move; front: turn; ends: width). Nothing reaches the sim.
const PLACE_R := 16.0          # a handle's drawn radius, screen px
const PH_BODY := 0
const PH_FRONT := 1
const PH_END_A := 2
const PH_END_B := 3
var place_on := false
var place_kind := ""           # "line" (a, b = preview_a / preview_b) | "group" (the selection's shape)
var place_layout: Array = []   # [{unit, centre (world px), facing, width, files}]
var place_handles: Array = []  # [{id, pos (world px)}]
var place_hot := -1            # the handle being dragged
var place_note := ""           # a word by the front handle ("facing the enemy")
var place_clamped := false     # the line is one rank long


func _draw_place(lw: float) -> void:
	var edge := Color(1.0, 0.92, 0.55, 0.95)
	var fill := Color(1.0, 0.92, 0.55, 0.14)
	if place_kind == "line":
		var ok := preview_ok
		var cl := preview_clamped
		preview_ok = true
		preview_clamped = place_clamped
		_draw_preview(lw)
		preview_ok = ok
		preview_clamped = cl
	for p in place_layout:
		var u: int = p["unit"]
		if u < sim.n_units:
			_draw_footprint(u, p["centre"], p["facing"], p["files"], sim.u_alive[u], edge, fill, lw)
	var hr := PLACE_R / zoom
	for h in place_handles:
		var id: int = h["id"]
		var pos: Vector2 = h["pos"]
		var hot := id == place_hot
		_up(pos)
		var rr := hr * (1.2 if hot else 1.0)
		draw_circle(pos, rr * 1.12, Color(0, 0, 0, 0.45))
		draw_circle(pos, rr, Color(0.16, 0.12, 0.05, 0.88))
		draw_arc(pos, rr, 0.0, TAU, 24, Color(1.0, 0.85, 0.35) if hot else edge, lw * 1.6)
		var g := Color(1.0, 0.93, 0.6)
		var k := rr * 0.5
		if id == PH_BODY:
			draw_line(pos + Vector2(-k, 0), pos + Vector2(k, 0), g, lw * 1.6)
			draw_line(pos + Vector2(0, -k), pos + Vector2(0, k), g, lw * 1.6)
			for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
				var t: Vector2 = pos + d * k
				var n := Vector2(-d.y, d.x) * k * 0.4
				draw_colored_polygon(PackedVector2Array([t + d * k * 0.3, t - d * k * 0.15 + n, t - d * k * 0.15 - n]), g)
		elif id == PH_FRONT:
			var ang := place_face_angle()
			var fd := Vector2(cos(ang), sin(ang))
			if BoardView.oblique:
				fd = Vector2(fd.x, fd.y * BoardView.OBLIQUE_COS).normalized()
			var side := Vector2(-fd.y, fd.x)
			draw_colored_polygon(PackedVector2Array([pos + fd * k * 1.15, pos - fd * k * 0.6 + side * k * 0.8,
				pos - fd * k * 0.6 - side * k * 0.8]), g)
		else:
			var ang2 := place_face_angle() + PI * 0.5
			var ed := Vector2(cos(ang2), sin(ang2))
			if BoardView.oblique:
				ed = Vector2(ed.x, ed.y * BoardView.OBLIQUE_COS).normalized()
			if id == PH_END_A:
				ed = -ed
			var sd := Vector2(-ed.y, ed.x)
			draw_line(pos - ed * k * 0.2, pos + ed * k * 0.9, g, lw * 1.6)
			draw_line(pos + ed * k * 0.9 - sd * k * 0.5, pos + ed * k * 0.9 + sd * k * 0.5, g, lw * 1.6)
			draw_line(pos - ed * k * 0.2, pos - ed * k * 0.9, g, lw * 1.6)
		if id == PH_FRONT and place_note != "":
			var fs := _font_size(12.0)
			_dstr(pos + Vector2(rr * 1.5, -rr * 0.2), place_note, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1.0, 0.9, 0.5))
		_flat()


var place_face := 0   # the ghost's facing (0..1023), set by the battle


func place_face_angle() -> float:
	return place_face * TAU / 1024.0
