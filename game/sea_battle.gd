extends Node2D
## The real-time sea battle screen (N3a; docs/DESIGN.md "Sea battles (as
## built, N3a)"). View only: it runs sim/sea_sim.gd at 10 ticks a second
## (pause, 1x, 2x, 4x), draws it interpolated between ticks and turns taps
## into sim orders (queued with the sim's own tick; a later live co-op
## would route them through sim/lockstep.gd, which already runs a SeaSim).
##
## Touch first (phones and tablets; the mouse emulates touch): tap a ship
## of yours to select it (tap it again: only it; double-tap: the whole
## fleet), long-press and drag for a box; with ships selected tap the sea
## to sail there (the course is planned by the wind and drawn: tacks
## included), tap an enemy to engage her (broadside on, focused fire) or,
## with Board armed, to lay alongside and board; one finger drags the view,
## two pinch to zoom (the wheel zooms too). The bottom bar sets the
## selected ships' sails (full / battle / heave to), shot (round / chain /
## grape), fire at will, target, board, hold course, flee. The left column
## lists your ships (hull, crew, rigging, loaded broadsides); the wind rose
## sits top left.
##
## Drawn: the sea with waves running before the wind, land and shoals from
## the sim's grid (smoothed), top-down hulls with gunports, sails that
## brace round with the wind and tear with the rigging, flags (white when
## struck), wakes, broadside smoke and muzzle flashes drifting downwind
## (the land battle's gun-smoke look), shot splashes and splinters, fires,
## the magazine blast, sinking and wreckage, grapples.

signal exit_requested

const SeaSim := preload("res://sim/sea_sim.gd")
const ST := preload("res://sim/sea_types.gd")
const FM := preload("res://sim/fixed_math.gd")
const Kit := preload("res://game/campaign/ui_kit.gd")
const AudioFx := preload("res://game/audio.gd")

const TICK_SEC := 0.1
const MAX_STEPS := 4
const ZOOM_MIN := 0.12
const ZOOM_MAX := 3.0
const DRAG_PX := 16.0
const LONG_PRESS := 0.35
const DOUBLE_TAP := 0.35
const SMOKE_LIFE := 9.0
const SMOKE_CAP := 420
const COL_SEA := Color(0.13, 0.36, 0.5)
const COL_SEA_DEEP := Color(0.09, 0.27, 0.4)
const COL_GUNSMOKE := Color(0.93, 0.93, 0.9)
const COL_SAIL := Color(0.96, 0.94, 0.86)
const COL_HULL := Color(0.42, 0.27, 0.16)
const COL_DECK := Color(0.68, 0.55, 0.37)
const SIDE_COLS := [Color(0.25, 0.55, 0.95), Color(0.9, 0.3, 0.25)]
const SPEEDS := [0, 4, 8, 16]   # quarter steps: pause, 1x, 2x, 4x
const LAND_UP := 3               # land texture pixels a grid cell (smoothed between cells)
const VIS := 1.5                 # ships drawn this much larger than their length (to read on a phone)

# ---- set by whoever opens it ----
var scenario: Dictionary = {}
var seed_value := 1
var player_side := 0
var campaign_mode := false
var title_text := "Sea battle"
var side_names := ["Your fleet", "The enemy"]
var side_cols: Array = SIDE_COLS.duplicate()
var coop = null              # (no live co-op at sea yet: the campaign screen checks it)
var interactive := true

var sim: SeaSim
var speed_q := 4
var _acc := 0.0
var _clock := 0.0
var _px := PackedFloat32Array()   # positions and headings before the last step (interpolation)
var _py := PackedFloat32Array()
var _ph := PackedFloat32Array()
var _wake: Array = []              # per ship: PackedVector2Array of recent positions
var _wake_t := 0.0
var selection: Array[int] = []
var arm := ""                      # "board": the next enemy tapped is boarded
var _ev_seen := 0
var _decided_at := -1.0
var _end_shown := false

# effects (view only)
var _sm_pos := PackedVector2Array()
var _sm_age := PackedFloat32Array()
var _sm_size := PackedFloat32Array()
var _fx: Array = []                # [kind, pos, age, a, b]: "splash", "hit", "flash", "blast", "shot", "debris"
var _msgs: Array = []              # [text, age, color]

# nodes
var camera: Camera2D
var _water: Node2D
var _land: Sprite2D
var _ships: Node2D
var _sky: Node2D
var _hud: CanvasLayer
var _cards: VBoxContainer
var _bar: HFlowContainer
var _info: Label
var _clock_lbl: Label
var _msg_lbl: Label
var _rose: Control
var _speed_btns: Array = []
var _end_panel: PanelContainer
var _leave_dlg: PanelContainer
var _card_nodes := {}

# input
var _touch := {}
var _press_pos := Vector2.ZERO
var _press_t := 0.0
var _dragging := false
var _boxing := false
var _box_a := Vector2.ZERO
var _box_b := Vector2.ZERO
var _pinch_d := 0.0
var _last_tap_t := -10.0
var _last_tap_ship := -1


func _ready() -> void:
	sim = SeaSim.new()
	sim.setup(scenario, seed_value)
	var n := sim.n_units
	_px.resize(n)
	_py.resize(n)
	_ph.resize(n)
	for s in n:
		_wake.append(PackedVector2Array())
	_snap_prev()
	_water = Node2D.new()
	_water.draw.connect(_draw_water)
	add_child(_water)
	_land = Sprite2D.new()
	_land.centered = false
	_land.texture = _land_texture()
	_land.scale = Vector2(SeaSim.CELL_M, SeaSim.CELL_M) / float(LAND_UP)
	_land.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	add_child(_land)
	_ships = Node2D.new()
	_ships.draw.connect(_draw_ships)
	add_child(_ships)
	_sky = Node2D.new()
	_sky.draw.connect(_draw_sky)
	add_child(_sky)
	camera = Camera2D.new()
	add_child(camera)
	camera.make_current()
	_frame_fleet()
	_build_hud()
	AudioFx.enter_battle()
	for s in n:
		if sim.u_side[s] == player_side:
			selection.append(s)
			break
	_refresh_bar()


func _exit_tree() -> void:
	AudioFx.leave_battle()


func is_decided() -> bool:
	return sim != null and sim.is_decided()


# ------------------------------------------------------------------ ticking ---

func _snap_prev() -> void:
	for s in sim.n_units:
		_px[s] = sim.s_x[s] / 1024.0
		_py[s] = sim.s_y[s] / 1024.0
		_ph[s] = sim.heading(s) * TAU / 1024.0


func _process(delta: float) -> void:
	_clock += delta
	if sim.ended == 0 or _clock - _decided_at < 6.0:
		_acc += delta * speed_q / 4.0
	var steps := 0
	while _acc >= TICK_SEC and steps < MAX_STEPS:
		_snap_prev()
		sim.step()
		_acc -= TICK_SEC
		steps += 1
	if steps >= MAX_STEPS:
		_acc = 0.0
	_events()
	_wake_t += delta
	if _wake_t >= 0.4:
		_wake_t = 0.0
		for s in sim.n_units:
			var w: PackedVector2Array = _wake[s]
			if sim.u_state[s] == SeaSim.S_SUNK or sim.u_state[s] == SeaSim.S_FLED:
				if not w.is_empty():
					w.remove_at(0)
			else:
				w.append(_pos(s))
				if w.size() > 14:
					w.remove_at(0)
			_wake[s] = w
	_age_fx(delta)
	if sim.decided_tick >= 0 and _decided_at < 0.0:
		_decided_at = _clock
	if _decided_at >= 0.0 and not _end_shown and _clock - _decided_at > 3.5:
		_show_end()
	_water.queue_redraw()
	_ships.queue_redraw()
	_sky.queue_redraw()
	_rose.queue_redraw()
	_refresh_hud()


func _alpha() -> float:
	return clampf(_acc / TICK_SEC, 0.0, 1.0)


func _pos(s: int) -> Vector2:
	var a := _alpha()
	return Vector2(lerpf(_px[s], sim.s_x[s] / 1024.0, a), lerpf(_py[s], sim.s_y[s] / 1024.0, a))


func _head(s: int) -> float:
	return lerp_angle(_ph[s], sim.heading(s) * TAU / 1024.0, _alpha())


func _wind_to() -> Vector2:
	var a := (sim.w_from + 512) * TAU / 1024.0
	return Vector2(cos(a), sin(a))


# ------------------------------------------------------------------- events ---

func _events() -> void:
	var cap := SeaSim.EV_CAP
	if sim.ev_n - _ev_seen > cap:
		_ev_seen = sim.ev_n - cap
	while _ev_seen < sim.ev_n:
		var i := _ev_seen % cap
		_ev_seen += 1
		var k := sim.ev_k[i]
		var a := sim.ev_a[i]
		var c := sim.ev_c[i]
		match k:
			SeaSim.EV_BROADSIDE:
				_broadside_fx(a, sim.ev_b[i], c, sim.ev_d[i], sim.ev_e[i])
			SeaSim.EV_BLAST:
				_fx.append(["blast", _pos(a), 0.0, a, 0])
				for j in 14:
					_fx.append(["debris", _pos(a), 0.0, a, j])
				_msg("%s blows up!" % _name(a), Color(1, 0.6, 0.3))
				AudioFx.play("burst", 1.0, 0.0, "art")
			SeaSim.EV_GRAPPLE:
				_msg("%s grapples %s: boarders away!" % [_name(a), _name(c)], Color(1, 0.9, 0.5))
				AudioFx.play("charge", 0.7, 0.0, "melee")
			SeaSim.EV_TAKEN:
				if a >= 0:
					_msg("%s is taken by %s!" % [_name(c), _name(a)], _side_col(sim.u_side[a]))
				else:
					_msg("%s is taken as a prize." % _name(c), Color(0.9, 0.9, 0.9))
			SeaSim.EV_STRIKE:
				_msg("%s strikes her colours!" % _name(a), Color(0.95, 0.95, 0.95))
			SeaSim.EV_SINK:
				_msg("%s goes down." % _name(a), Color(0.6, 0.8, 1.0))
				for j in 8:
					_fx.append(["debris", _pos(a), 0.0, a, j + 20])
			SeaSim.EV_REPELLED:
				_msg("%s's boarders are thrown back." % _name(a), Color(0.9, 0.8, 0.7))
			SeaSim.EV_FIRE:
				_msg("Fire aboard %s!" % _name(a), Color(1, 0.55, 0.25))
			SeaSim.EV_GROUND:
				_msg("%s runs aground!" % _name(a), Color(0.95, 0.85, 0.6))
			SeaSim.EV_FLED:
				_msg("%s escapes." % _name(a), Color(0.85, 0.85, 0.85))


func _broadside_fx(s: int, side: int, t: int, hits: int, shot: int) -> void:
	var p := _pos(s)
	var h := _head(s)
	var fwd := Vector2(cos(h), sin(h))
	var sd := Vector2(-fwd.y, fwd.x) * (1.0 if side == 1 else -1.0)
	var ty := sim.s_type[s]
	var ln := float(ST.stat(ty, "len")) * VIS
	var bm := float(ST.stat(ty, "beam")) * VIS
	var guns := ST.stat(ty, "guns")
	var n := clampi(guns / 2 + 1, 1, 12)
	for i in n:
		var f := (float(i) + 0.5) / n - 0.5
		var at := p + fwd * f * ln * 0.75 + sd * (bm * 0.5 + 2.0)
		_puff(at + sd * 4.0, 3.2 + guns * 0.07)
		_fx.append(["flash", at + sd * 2.0, 0.0, 0, 0])
	var tp := _pos(t)
	var d := p.distance_to(tp)
	_fx.append(["shot", p + sd * bm, 0.0, t, shot])
	var miss := clampi(guns - hits, 0, 10)
	var tl := float(ST.stat(sim.s_type[t], "len")) * VIS
	for j in miss:
		var r := Vector2(sin(j * 2.3 + _clock * 7.0), cos(j * 1.7 + _clock * 3.0)) * (tl * 0.6 + 10.0 + (j % 4) * 6.0)
		_fx.append(["splash", tp + r, -d / 450.0 - j * 0.03, 0, 0])
	for j in clampi(hits, 0, 10):
		var r2 := Vector2(sin(j * 1.9), cos(j * 2.9)) * tl * 0.3
		_fx.append(["hit", tp + r2, -d / 450.0 - j * 0.03, shot, 0])
	var cam := camera.get_screen_center_position() if camera != null else p
	var vol := clampf(0.35 + guns / 40.0, 0.3, 1.0) * clampf(1.0 - p.distance_to(cam) / 1800.0, 0.25, 1.0)
	AudioFx.play("cannon", vol, clampf((p.x - cam.x) / 900.0, -0.8, 0.8), "art")


func _puff(at: Vector2, sz: float) -> void:
	while _sm_age.size() >= SMOKE_CAP:
		_sm_pos.remove_at(0)
		_sm_age.remove_at(0)
		_sm_size.remove_at(0)
	_sm_pos.append(at)
	_sm_age.append(0.0)
	_sm_size.append(sz)


func _age_fx(delta: float) -> void:
	var dt := delta * maxf(speed_q / 4.0, 0.0) if speed_q > 0 else 0.0
	var k := 0
	while k < _sm_age.size():
		_sm_age[k] += dt
		if _sm_age[k] > SMOKE_LIFE:
			_sm_pos.remove_at(k)
			_sm_age.remove_at(k)
			_sm_size.remove_at(k)
		else:
			k += 1
	var keep: Array = []
	for f in _fx:
		f[2] = float(f[2]) + dt
		var life := 1.2
		match str(f[0]):
			"blast":
				life = 3.0
			"debris":
				life = 14.0
			"shot":
				life = 0.45
			"flash":
				life = 0.18
			"splash":
				life = 1.4
			"hit":
				life = 1.0
		if float(f[2]) < life:
			keep.append(f)
	_fx = keep
	var km: Array = []
	for m in _msgs:
		m[1] = float(m[1]) + delta
		if float(m[1]) < 4.5:
			km.append(m)
	_msgs = km


func _msg(text: String, col: Color) -> void:
	_msgs.append([text.substr(0, 1).to_upper() + text.substr(1), 0.0, col])
	if _msgs.size() > 4:
		_msgs.remove_at(0)


func _name(s: int) -> String:
	if s < 0 or s >= sim.n_units:
		return "?"
	var d: Dictionary = (scenario.get("units", []) as Array)[s]
	if d.has("nm"):
		return str(d["nm"])
	var own := "your" if sim.u_side[s] == player_side else "the enemy"
	return "%s %s" % [own, ST.name_of(sim.s_type[s]).to_lower()]


func _side_col(side: int) -> Color:
	return side_cols[clampi(side, 0, 1)]


func _ship_col(s: int) -> Color:
	var d: Dictionary = (scenario.get("units", []) as Array)[s]
	if d.has("col"):
		var c: Array = d["col"]
		return Color(float(c[0]), float(c[1]), float(c[2]))
	return _side_col(sim.u_side[s])


# ----------------------------------------------------------------- drawing ---

func _land_texture() -> Texture2D:
	var gw := sim.g_w
	var gh := sim.g_h
	var img := Image.create(gw * LAND_UP, gh * LAND_UP, false, Image.FORMAT_RGBA8)
	var val := PackedFloat32Array()
	val.resize(gw * gh)
	for c in gw * gh:
		val[c] = [0.0, 0.5, 1.0][sim.g[c]]
	var any := false
	for c in gw * gh:
		if sim.g[c] != 0:
			any = true
			break
	if not any:
		img.fill(Color(0, 0, 0, 0))
		return ImageTexture.create_from_image(img)
	# A soft blur over the cells first: the coast comes out round, not stepped.
	for pass_i in 2:
		var bl := PackedFloat32Array()
		bl.resize(gw * gh)
		for gy in gh:
			for gx in gw:
				var acc := 0.0
				var wsum := 0.0
				for dy in [-1, 0, 1]:
					for dx in [-1, 0, 1]:
						var x2: int = clampi(gx + dx, 0, gw - 1)
						var y2: int = clampi(gy + dy, 0, gh - 1)
						var wgt := 4.0 if dx == 0 and dy == 0 else (2.0 if dx == 0 or dy == 0 else 1.0)
						acc += val[y2 * gw + x2] * wgt
						wsum += wgt
				bl[gy * gw + gx] = acc / wsum
		val = bl
	var up := float(LAND_UP)
	for y in gh * LAND_UP:
		var fy := (y + 0.5) / up - 0.5
		var y0 := clampi(int(floor(fy)), 0, gh - 1)
		var y1 := clampi(y0 + 1, 0, gh - 1)
		var ty := clampf(fy - floor(fy), 0.0, 1.0)
		for x in gw * LAND_UP:
			var fx := (x + 0.5) / up - 0.5
			var x0 := clampi(int(floor(fx)), 0, gw - 1)
			var x1 := clampi(x0 + 1, 0, gw - 1)
			var tx := clampf(fx - floor(fx), 0.0, 1.0)
			var v := lerpf(lerpf(val[y0 * gw + x0], val[y0 * gw + x1], tx), lerpf(val[y1 * gw + x0], val[y1 * gw + x1], tx), ty)
			var col := Color(0, 0, 0, 0)
			if v > 0.74:
				var g := clampf((v - 0.74) * 5.0, 0.0, 1.0)
				col = Color(0.85, 0.78, 0.55).lerp(Color(0.33, 0.5, 0.26), g)
				var n := sin(x * 0.37 + y * 0.21) * 0.03 + sin(x * 0.11 - y * 0.29) * 0.04
				col = col.darkened(n + 0.04)
			elif v > 0.66:
				col = Color(0.9, 0.84, 0.62)
			elif v > 0.2:
				col = Color(0.55, 0.82, 0.78, 0.2 + (v - 0.2) * 1.0)
			img.set_pixel(x, y, col)
	var tex := ImageTexture.create_from_image(img)
	return tex


func _draw_water() -> void:
	var w := float(sim.field_w)
	var h := float(sim.field_h)
	_water.draw_rect(Rect2(-2000, -2000, w + 4000, h + 4000), COL_SEA_DEEP)
	_water.draw_rect(Rect2(0, 0, w, h), COL_SEA)
	# Waves running before the wind: crests drifting downwind, fading in and out.
	var wt := _wind_to()
	var perp := Vector2(-wt.y, wt.x)
	var spd := 3.0 + sim.w_str * 0.06
	var vr := _view_rect().grow(40.0)
	var step := 90.0
	var zoom := camera.zoom.x if camera != null else 1.0
	if zoom < 0.3:
		step = 180.0
	var x0 := floorf(vr.position.x / step) * step
	var y0 := floorf(vr.position.y / step) * step
	var yy := y0
	var lw := 1.3 / maxf(zoom, 0.2)
	while yy < vr.end.y:
		var xx := x0
		while xx < vr.end.x:
			var hsh := absf(sin(xx * 12.9898 + yy * 78.233) * 43758.5453)
			var fr := hsh - floorf(hsh)
			var ph := fposmod(_clock * 0.18 + fr * 7.0, 1.0)
			var c := Vector2(xx + fr * step, yy + fposmod(fr * 13.0, 1.0) * step) + wt * spd * (ph * 8.0)
			var a := sin(ph * PI) * 0.16
			var ln := 14.0 + fr * 18.0
			var arc := PackedVector2Array()
			for k in 5:
				var t := float(k) / 4.0 - 0.5
				arc.append(c + perp * ln * t - wt * ln * 0.22 * (1.0 - 4.0 * t * t))
			_water.draw_polyline(arc, Color(0.8, 0.9, 0.96, a), lw)
			if fr > 0.82:
				_water.draw_circle(c + wt * 2.0, lw * 1.2, Color(1, 1, 1, a * 0.8))
			xx += step
		yy += step
	# The field's edge (beyond it ships have left the battle).
	_water.draw_rect(Rect2(0, 0, w, h), Color(1, 1, 1, 0.08), false, 3.0 / maxf(zoom, 0.2))


func _view_rect() -> Rect2:
	if camera == null:
		return Rect2(0, 0, sim.field_w, sim.field_h)
	var vs := get_viewport_rect().size / camera.zoom
	return Rect2(camera.get_screen_center_position() - vs * 0.5, vs)


func _draw_ships() -> void:
	var zoom := camera.zoom.x
	var lw := 1.0 / maxf(zoom, 0.15)
	# Wakes first.
	for s in sim.n_units:
		var wk: PackedVector2Array = _wake[s]
		if wk.size() < 2:
			continue
		var p := _pos(s)
		var pts := wk.duplicate()
		if sim.u_state[s] != SeaSim.S_SUNK and sim.u_state[s] != SeaSim.S_FLED:
			pts.append(p)
		var bm := float(ST.stat(sim.s_type[s], "beam"))
		for i in range(1, pts.size()):
			var f := float(i) / pts.size()
			_ships.draw_line(pts[i - 1], pts[i], Color(0.92, 0.97, 1.0, 0.18 * f), bm * (1.6 - f), true)
	# Debris and splashes on the water.
	for f in _fx:
		var age := float(f[2])
		if age < 0.0:
			continue
		match str(f[0]):
			"splash":
				var r := 3.0 + age * 9.0
				_ships.draw_circle(f[1], r, Color(0.95, 0.98, 1.0, 0.55 * (1.0 - age / 1.4)))
				if age < 0.35:
					_ships.draw_circle(f[1], 2.5, Color(1, 1, 1, 0.9))
			"debris":
				var s2 := int(f[3])
				var j := int(f[4])
				var ang := j * 2.4 + s2
				var out := (18.0 if j < 20 else 8.0) + minf(age, 2.0) * (14.0 if j < 20 else 5.0)
				var dp := Vector2(f[1]) + Vector2(cos(ang), sin(ang)) * out + _wind_to() * age * 1.2
				var al := clampf(1.0 - age / 14.0, 0.0, 1.0) * 0.85
				_ships.draw_line(dp, dp + Vector2(cos(ang * 3.0), sin(ang * 3.0)) * (4.0 + j % 4), Color(0.35, 0.24, 0.14, al), 1.8 * lw + 1.0)
	for s in sim.n_units:
		_draw_ship(s, lw)
	# Grapples: lines across, the melee on the decks (sparks), a ring round both.
	for s in sim.n_units:
		var o := sim.s_grap[s]
		if o > s:
			var a := _draw_pos(s)
			var b := _draw_pos(o)
			for k in 4:
				var off := Vector2(sin(k * 2.1), cos(k * 1.3)) * 7.0
				_ships.draw_line(a + off, b - off, Color(0.15, 0.1, 0.06, 0.95), 1.4 * lw + 0.6)
			var mid := (a + b) * 0.5
			var rad := a.distance_to(b) * 0.5 + float(ST.stat(sim.s_type[s], "len")) * VIS * 0.55
			_ships.draw_arc(mid, rad + 2.0 * sin(_clock * 5.0), 0, TAU, 36, Color(1, 0.8, 0.3, 0.85), 2.5 * lw, true)
			for k2 in 10:
				var ang2 := _clock * 7.0 + k2 * 2.4
				var sp := mid + Vector2(cos(ang2), sin(ang2 * 1.3)) * (4.0 + (k2 % 3) * 5.0)
				var fl := absf(sin(_clock * 13.0 + k2))
				_ships.draw_circle(sp, (1.2 + 1.5 * fl) * lw + 0.6, Color(1, 0.95, 0.6, 0.5 + 0.5 * fl))
	# Orders: courses, targets, the selection.
	_draw_orders(lw)
	if _boxing:
		var r2 := Rect2(_box_a, _box_b - _box_a).abs()
		_ships.draw_rect(r2, Color(1, 1, 1, 0.12))
		_ships.draw_rect(r2, Color(1, 1, 1, 0.8), false, 1.5 * lw)


func _draw_ship(s: int, lw: float) -> void:
	var st := sim.u_state[s]
	var age_end := (sim.tick - sim.s_end_t[s]) * TICK_SEC if sim.s_end_t[s] >= 0 else 0.0
	if st == SeaSim.S_FLED:
		return
	var sink := 0.0
	if st == SeaSim.S_SUNK:
		if sim.s_blown[s] != 0 or age_end > 6.0:
			return
		sink = clampf(age_end / 6.0, 0.0, 1.0)
	var ty := sim.s_type[s]
	var ln := float(ST.stat(ty, "len")) * VIS
	var bm := float(ST.stat(ty, "beam")) * VIS
	var p := _draw_pos(s)
	var h := _head(s) + sink * 0.5
	var fwd := Vector2(cos(h), sin(h))
	var sd := Vector2(-fwd.y, fwd.x)
	var xf := Transform2D(fwd, sd, p)
	var shrink := 1.0 - sink * 0.35
	var hull := PackedVector2Array([Vector2(ln * 0.5, 0), Vector2(ln * 0.3, bm * 0.5), Vector2(-ln * 0.38, bm * 0.5),
		Vector2(-ln * 0.5, bm * 0.36), Vector2(-ln * 0.5, -bm * 0.36), Vector2(-ln * 0.38, -bm * 0.5), Vector2(ln * 0.3, -bm * 0.5)])
	var oars := ST.stat(ty, "oars") != 0
	if oars:
		hull = PackedVector2Array([Vector2(ln * 0.5, 0), Vector2(ln * 0.25, bm * 0.5), Vector2(-ln * 0.3, bm * 0.5),
			Vector2(-ln * 0.5, 0), Vector2(-ln * 0.3, -bm * 0.5), Vector2(ln * 0.25, -bm * 0.5)])
	var world := PackedVector2Array()
	for v in hull:
		world.append(xf * (v * shrink))
	var fade := 1.0 - sink
	# Shadow / waterline foam.
	var sh := PackedVector2Array()
	for v in hull:
		sh.append(xf * (v * 1.12 * shrink))
	_ships.draw_colored_polygon(sh, Color(0.9, 0.97, 1.0, 0.18 * fade))
	_ships.draw_colored_polygon(world, Color(COL_HULL, fade))
	var deck := PackedVector2Array()
	for v in hull:
		deck.append(xf * (v * 0.78 * shrink))
	_ships.draw_colored_polygon(deck, Color(COL_DECK.darkened(0.15 if st != SeaSim.S_SAIL else 0.0), fade))
	var col := _ship_col(s)
	var rail := world.duplicate()
	rail.append(world[0])
	_ships.draw_polyline(rail, Color(col, 0.95 * fade), maxf(1.2, bm * 0.12), true)
	if sink > 0.0:
		_ships.draw_arc(p, ln * 0.6 * (0.5 + sink), 0, TAU, 24, Color(0.9, 0.97, 1.0, 0.5 * (1.0 - sink)), 2.0 * lw)
		return
	# Gunports.
	var guns := clampi(ST.stat(ty, "guns"), 0, 18)
	var gp := clampi(guns / 2 + 1, 1, 9) if guns > 0 else 0
	for i in gp:
		var f := (float(i) + 0.5) / gp - 0.5
		for sg in [-1.0, 1.0]:
			_ships.draw_circle(xf * Vector2(f * ln * 0.66, sg * bm * 0.44), maxf(bm * 0.07, 0.6), Color(0.08, 0.06, 0.05))
	# A treasure galleon: the stern castle gilded.
	var d: Dictionary = (scenario.get("units", []) as Array)[s]
	if int(d.get("g", 0)) > 0 or ty == ST.index_of("galleon"):
		var castle := PackedVector2Array([xf * Vector2(-ln * 0.47, -bm * 0.33), xf * Vector2(-ln * 0.3, -bm * 0.38),
			xf * Vector2(-ln * 0.3, bm * 0.38), xf * Vector2(-ln * 0.47, bm * 0.33)])
		_ships.draw_colored_polygon(castle, Color(0.85, 0.7, 0.3) if int(d.get("g", 0)) > 0 else COL_HULL.lightened(0.15))
	if oars:
		# Paddlers: strokes along both sides.
		for i in 5:
			var f2 := (float(i) + 0.5) / 5.0 - 0.5
			var sw := sin(_clock * 6.0 + i) * 0.4 if st == SeaSim.S_SAIL and sim.s_spd[s] > 50 else 0.0
			for sg2 in [-1.0, 1.0]:
				var a0: Vector2 = xf * Vector2(f2 * ln * 0.7, sg2 * bm * 0.5)
				var a1: Vector2 = xf * Vector2(f2 * ln * 0.7 + sw * bm, sg2 * bm * 1.4)
				_ships.draw_line(a0, a1, Color(0.3, 0.2, 0.1), maxf(0.8, bm * 0.15))
	else:
		_draw_rig(s, xf, ln, bm, lw)
	# Flag at the stern: her colour, white when struck, the captor's when taken.
	var fc := col
	if st == SeaSim.S_STRUCK:
		fc = Color(0.97, 0.97, 0.97)
	elif st == SeaSim.S_TAKEN and sim.s_by[s] >= 0:
		fc = _side_col(sim.s_by[s])
	var fp: Vector2 = xf * Vector2(-ln * 0.5, 0)
	var wt := _wind_to()
	var fl := maxf(ln * 0.22, 5.0)
	var flap := Vector2(-wt.y, wt.x) * sin(_clock * 9.0 + s) * fl * 0.12
	var flag := PackedVector2Array([fp, fp + wt * fl + flap, fp + wt * fl + flap + Vector2(-wt.y, wt.x) * fl * 0.55,
		fp + Vector2(-wt.y, wt.x) * fl * 0.55])
	_ships.draw_colored_polygon(flag, fc)
	_ships.draw_polyline(flag, Color(0, 0, 0, 0.5), 0.6 * lw, true)
	# Fire aboard.
	if sim.s_burn[s] > 0:
		for k in 5:
			var fpos: Vector2 = xf * Vector2((sin(k * 1.7 + s) * 0.3) * ln, cos(k * 2.3) * bm * 0.25)
			var fl2 := 2.0 + 2.5 * absf(sin(_clock * 11.0 + k))
			_ships.draw_circle(fpos, fl2 + bm * 0.1, Color(1.0, 0.45 + 0.3 * absf(sin(_clock * 7.0 + k)), 0.1, 0.85))
	# Selection ring and a small health bar for every ship.
	if selection.has(s):
		_ships.draw_arc(p, ln * 0.62 + 4.0, 0, TAU, 32, Color(1, 1, 1, 0.9), 2.0 * lw, true)
	if st == SeaSim.S_SAIL:
		var bw := maxf(ln, 26.0 * lw)
		var bp := p + Vector2(-bw * 0.5, -ln * 0.55 - 10.0 * lw)
		var hp := float(sim.s_hull[s]) / sim.s_hull0[s]
		var cp := float(sim.s_crew[s]) / maxi(sim.s_crew0[s], 1)
		_ships.draw_rect(Rect2(bp, Vector2(bw, 3.5 * lw)), Color(0, 0, 0, 0.55))
		_ships.draw_rect(Rect2(bp, Vector2(bw * hp, 3.5 * lw)), Color(0.45, 0.85, 0.4) if hp > 0.5 else Color(0.95, 0.7, 0.25) if hp > 0.25 else Color(0.95, 0.3, 0.25))
		_ships.draw_rect(Rect2(bp + Vector2(0, 4.0 * lw), Vector2(bw, 2.5 * lw)), Color(0, 0, 0, 0.55))
		_ships.draw_rect(Rect2(bp + Vector2(0, 4.0 * lw), Vector2(bw * cp, 2.5 * lw)), Color(0.6, 0.75, 1.0))
		_ships.draw_rect(Rect2(bp + Vector2(-5.0 * lw, 0), Vector2(3.5 * lw, 6.5 * lw)), _side_col(sim.u_side[s]))


## Masts and sails: square sails braced round with the wind (fore-and-aft
## on a sloop), bellied by the drive, torn and fewer as the rigging goes,
## furled when she heaves to or strikes.
## Where ship s is drawn: her place, but a boarder lying alongside is drawn
## clear of her prize (the hulls are drawn VIS x their size).
func _draw_pos(s: int) -> Vector2:
	var p := _pos(s)
	var o := sim.s_grap[s]
	if o < 0 or sim.s_boarder[s] == 0:
		return p
	var d := p - _pos(o)
	if d.length() < 0.01:
		d = Vector2.RIGHT
	var extra := (VIS - 1.0) * (ST.stat(sim.s_type[s], "beam") + ST.stat(sim.s_type[o], "beam")) * 0.5 + 1.0
	return p + d.normalized() * extra


func _draw_rig(s: int, xf: Transform2D, ln: float, bm: float, lw: float) -> void:
	var ty := sim.s_type[s]
	var key := str(ST.row(ty)["key"])
	var masts: Array = [0.3, 0.02, -0.25]
	if key == "sloop":
		masts = [0.12]
	elif key == "brigantine":
		masts = [0.22, -0.12]
	var rig := float(sim.s_rig[s]) / maxi(sim.s_rig0[s], 1)
	var furled := sim.s_sail[s] == 0 or sim.u_state[s] != SeaSim.S_SAIL
	var h := sim.heading(s)
	var rel := FM.angle_diff(h, (sim.w_from + 512) & 1023)   # 0: running, +-512: head to wind
	var drv := sim.drive(s, h) / 100.0
	var wt := _wind_to()
	var span := bm * 1.9
	var brace := clampf(rel * 0.55, -150.0, 150.0) * TAU / 1024.0
	for i in masts.size():
		var mp: Vector2 = xf * Vector2(float(masts[i]) * ln, 0)
		if rig < 0.3 and i > 0:
			# Shot away: a stump and wreckage alongside.
			_ships.draw_circle(mp, bm * 0.1, Color(0.2, 0.13, 0.08))
			continue
		if key == "sloop":
			# The boom swings to leeward.
			var off := absi(FM.angle_diff(h, sim.w_from))
			var swing := clampf((512 - off) * 0.45, 20.0, 230.0) * TAU / 1024.0
			var lee := 1.0 if FM.angle_diff(h, sim.w_from) < 0 else -1.0
			var aft: Vector2 = (xf.basis_xform(Vector2(-1, 0))).rotated(lee * swing)
			var tip := mp + aft * ln * 0.55
			if furled:
				_ships.draw_line(mp, tip, Color(COL_SAIL, 0.9), 1.6 * lw)
			else:
				var belly := Vector2(-aft.y, aft.x) * lee * -1.0 * ln * 0.12 * drv
				var tri := PackedVector2Array([mp, mp + (tip - mp) * 0.5 + belly, tip, mp + (tip - mp) * 0.5 + belly * 0.4])
				_ships.draw_colored_polygon(tri, Color(COL_SAIL, 0.95))
				_ships.draw_polyline(PackedVector2Array([mp, mp + (tip - mp) * 0.5 + belly, tip]), Color(0, 0, 0, 0.25), 0.6 * lw)
			_ships.draw_circle(mp, bm * 0.12, Color(0.25, 0.17, 0.1))
			continue
		var yard: Vector2 = xf.basis_xform(Vector2(0, 1)).rotated(brace)
		var a := mp - yard * span * 0.5
		var b := mp + yard * span * 0.5
		if furled:
			_ships.draw_line(a, b, Color(COL_SAIL.darkened(0.1), 0.95), maxf(1.2, bm * 0.14))
		else:
			var fwd: Vector2 = xf.basis_xform(Vector2(1, 0))
			var belly2 := (fwd * 0.75 + wt * 0.25).normalized() * bm * (0.25 + 0.55 * drv) * (0.6 + 0.4 * rig)
			var sail := PackedVector2Array()
			for k in 9:
				var t := float(k) / 8.0
				sail.append(a.lerp(b, t) + belly2 * sin(t * PI))
			for k in 9:
				var t2 := 1.0 - float(k) / 8.0
				sail.append(a.lerp(b, t2) + belly2 * sin(t2 * PI) * 0.35)
			_ships.draw_colored_polygon(sail, Color(COL_SAIL, 0.96))
			_ships.draw_polyline(sail.slice(0, 9), Color(0, 0, 0, 0.22), 0.6 * lw)
			# Holes as the rigging is shot through.
			var holes := int((1.0 - rig) * 6.0)
			for k2 in holes:
				var hp := a.lerp(b, fposmod(k2 * 0.37 + s * 0.11, 1.0)) + belly2 * (0.4 + 0.3 * sin(k2 * 3.1))
				_ships.draw_circle(hp, maxf(bm * 0.09, 0.7), Color(0.12, 0.3, 0.4, 0.85))
		_ships.draw_circle(mp, bm * 0.11, Color(0.25, 0.17, 0.1))


func _draw_orders(lw: float) -> void:
	for s in sim.n_units:
		if sim.u_side[s] != player_side or sim.u_state[s] != SeaSim.S_SAIL:
			continue
		var sel := selection.has(s)
		var al := 0.9 if sel else 0.35
		var p := _pos(s)
		match sim.s_mode[s]:
			SeaSim.M_GOTO:
				var g := Vector2(sim.s_tx[s], sim.s_ty[s]) / 1024.0
				var pts := course_points(s)
				for i in range(1, pts.size()):
					_dashed(pts[i - 1], pts[i], Color(1, 1, 0.85, al), 1.6 * lw, 10.0 * lw)
				_ships.draw_arc(g, 9.0 * lw + 3.0, 0, TAU, 20, Color(1, 1, 0.85, al), 1.6 * lw)
				if pts.size() > 2:
					_ships.draw_circle(pts[1], 3.0 * lw + 1.0, Color(1, 0.9, 0.5, al))
			SeaSim.M_ENGAGE, SeaSim.M_BOARD:
				var t := sim.s_tgt[s]
				if t >= 0:
					var tp := _pos(t)
					var c := Color(1, 0.35, 0.3, al) if sim.s_mode[s] == SeaSim.M_ENGAGE else Color(1, 0.85, 0.3, al)
					_dashed(p, tp, c, 1.6 * lw, 8.0 * lw)
					var tl := float(ST.stat(sim.s_type[t], "len")) * VIS
					_ships.draw_arc(tp, tl * 0.62 + 6.0, 0, TAU, 28, c, 2.0 * lw, true)
			SeaSim.M_FLEE:
				var fpts := course_points(s)
				for i in range(1, fpts.size()):
					_dashed(fpts[i - 1], fpts[i], Color(0.8, 0.8, 0.8, al * 0.7), 1.2 * lw, 6.0 * lw)
		if sel:
			# The broadsides' arcs and reach, loaded (white) or reloading (dim).
			var h := sim.heading(s)
			for k in 2:
				var ctr := ((h - 256) if k == 0 else (h + 256)) * TAU / 1024.0
				var rng := float(sim.shot_range(s, sim.s_ld[s * 2 + k]))
				var half := SeaSim.ARC * TAU / 1024.0
				var loaded := sim.s_rl[s * 2 + k] == 0
				var ac := Color(1, 1, 1, 0.22) if loaded else Color(1, 1, 1, 0.07)
				_ships.draw_arc(p, rng, ctr - half, ctr + half, 16, ac, 1.4 * lw)
				_ships.draw_line(p, p + Vector2(cos(ctr - half), sin(ctr - half)) * rng, ac, 1.0 * lw)
				_ships.draw_line(p, p + Vector2(cos(ctr + half), sin(ctr + half)) * rng, ac, 1.0 * lw)


func _dashed(a: Vector2, b: Vector2, c: Color, w: float, dash: float) -> void:
	var d := a.distance_to(b)
	if d < 1.0:
		return
	var n := int(d / (dash * 2.0)) + 1
	for i in n:
		var t0 := float(i) * dash * 2.0 / d
		var t1 := minf(t0 + dash / d, 1.0)
		_ships.draw_line(a.lerp(b, t0), a.lerp(b, t1), c, w)


## The course ship s will sail to its goal (the navigator's: straight when
## it can lie the course, else close-hauled on its tack to the layline,
## then the other tack), as points in metres.
func course_points(s: int) -> PackedVector2Array:
	var p := _pos(s)
	var g := Vector2(sim.s_tx[s], sim.s_ty[s]) / 1024.0
	if sim.s_mode[s] == SeaSim.M_FLEE:
		g = Vector2(sim.s_flee_x[s], sim.s_flee_y[s]) / 1024.0
	var out := PackedVector2Array([p])
	if ST.stat(sim.s_type[s], "oars") != 0:
		out.append(g)
		return out
	var b := FM.atan2_a(int(g.y - p.y), int(g.x - p.x))
	var c := ST.stat(sim.s_type[s], "irons") * 1024 / 360 + 24
	var dd := FM.angle_diff(sim.w_from, b)
	if absi(dd) >= c:
		out.append(g)
		return out
	var tack := sim.s_tack[s]
	if tack == 0:
		tack = 1 if FM.angle_diff(sim.w_from, sim.heading(s)) >= 0 else -1
	var a1 := (sim.w_from + tack * c) * TAU / 1024.0
	var a2 := (sim.w_from - tack * c) * TAU / 1024.0
	var d1 := Vector2(cos(a1), sin(a1))
	var d2 := Vector2(cos(a2), sin(a2))
	# p + t d1 + u d2 = g
	var det := d1.x * d2.y - d1.y * d2.x
	if absf(det) < 1e-4:
		out.append(g)
		return out
	var r := g - p
	var t := (r.x * d2.y - r.y * d2.x) / det
	if t <= 0.0:
		out.append(g)
		return out
	out.append(p + d1 * t)
	out.append(g)
	return out


func _draw_sky() -> void:
	var zoom := camera.zoom.x
	var lw := 1.0 / maxf(zoom, 0.15)
	var wt := _wind_to()
	var drift := wt * (2.0 + sim.w_str * 0.03)
	# Smoke (the land battle's gun-smoke look, drifting with this wind).
	var vr := _view_rect().grow(60.0)
	for k in _sm_age.size():
		var a := _sm_age[k]
		var f := a / SMOKE_LIFE
		var sz := _sm_size[k]
		var p := _sm_pos[k] + drift * a
		if not vr.has_point(p):
			continue
		var r := sz * (1.2 + 4.0 * sqrt(f))
		var al := 0.4 * pow(1.0 - f, 1.3) * minf(1.0, a * 8.0)
		_sky.draw_circle(p, r, Color(COL_GUNSMOKE, al))
		var o := Vector2(((k * 7) % 5 - 2) * 0.35, ((k * 3) % 5 - 2) * 0.25) * r
		_sky.draw_circle(p + o, r * 0.75, Color(COL_GUNSMOKE, al * 0.8))
	# Smoke columns over burning ships.
	for s in sim.n_units:
		if sim.s_burn[s] > 0 and sim.u_state[s] != SeaSim.S_SUNK:
			var p2 := _pos(s)
			for k in 6:
				var t := fposmod(_clock * 0.35 + k / 6.0, 1.0)
				var c := p2 + drift * t * 14.0 + Vector2(sin(k * 1.3 + _clock), 0) * 3.0
				_sky.draw_circle(c, 4.0 + t * 16.0, Color(0.22, 0.2, 0.2, 0.5 * sin(PI * t)))
	for f2 in _fx:
		var age := float(f2[2])
		if age < 0.0:
			continue
		match str(f2[0]):
			"flash":
				_sky.draw_circle(f2[1], 3.5 * (1.0 - age / 0.18) + 1.0, Color(1.0, 0.85, 0.4, 0.95))
			"shot":
				var t2 := int(f2[3])
				var to := _pos(t2)
				var fr := clampf(age / 0.45, 0.0, 1.0)
				var a2: Vector2 = Vector2(f2[1]).lerp(to, fr)
				var col := Color(0.15, 0.15, 0.15, 0.7) if int(f2[4]) == ST.SHOT_ROUND else Color(0.3, 0.25, 0.2, 0.7)
				_sky.draw_line(a2, Vector2(f2[1]).lerp(to, maxf(fr - 0.15, 0.0)), col, 1.4 * lw)
			"hit":
				var r2 := 2.0 + age * 8.0
				var hc := Color(0.35, 0.22, 0.12, 0.8 * (1.0 - age)) if int(f2[3]) != ST.SHOT_GRAPE else Color(0.7, 0.2, 0.15, 0.7 * (1.0 - age))
				_sky.draw_circle(f2[1], r2, hc)
			"blast":
				var s3 := int(f2[3])
				var fa := age / 3.0
				var rr := 20.0 + 90.0 * sqrt(fa)
				# The shock ring, the fireball, then a pall of smoke drifting off.
				_sky.draw_arc(f2[1], rr * 1.4, 0, TAU, 40, Color(1, 1, 1, 0.55 * maxf(1.0 - fa * 2.0, 0.0)), 3.0 * lw)
				if fa > 0.12:
					for k2 in 7:
						var ang := k2 * 0.9 + s3
						var c2: Vector2 = Vector2(f2[1]) + drift * age * 5.0 + Vector2(cos(ang), sin(ang)) * (12.0 + 30.0 * fa)
						_sky.draw_circle(c2, 14.0 + 26.0 * fa, Color(0.28, 0.26, 0.25, 0.55 * (1.0 - fa)))
				var fb := maxf(1.0 - fa * 2.2, 0.0)
				_sky.draw_circle(f2[1], rr * 0.9, Color(1.0, 0.5, 0.12, 0.75 * fb))
				_sky.draw_circle(f2[1], rr * 0.6, Color(1.0, 0.78, 0.3, 0.85 * fb))
				_sky.draw_circle(f2[1], rr * 0.3, Color(1.0, 1.0, 0.85, 0.95 * maxf(1.0 - fa * 4.0, 0.0)))


# --------------------------------------------------------------------- HUD ---

func _build_hud() -> void:
	_hud = CanvasLayer.new()
	_hud.layer = 5
	add_child(_hud)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(root)
	# Top bar: the wind rose, title and clock, speed, leave.
	var top := HBoxContainer.new()
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 6
	top.offset_right = -6
	top.offset_top = 4
	top.add_theme_constant_override("separation", 6)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(top)
	_rose = Control.new()
	_rose.custom_minimum_size = Vector2(150, 56)
	_rose.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rose.draw.connect(_draw_rose)
	top.add_child(_rose)
	var mid := VBoxContainer.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mid.add_theme_constant_override("separation", 0)
	top.add_child(mid)
	var tl := Kit.label(title_text, Kit.FONT_SMALL, Kit.COL_GOLD)
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	tl.clip_text = true
	tl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mid.add_child(tl)
	_clock_lbl = Kit.label("0:00", Kit.FONT_SMALL, Color.WHITE)
	_clock_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_clock_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mid.add_child(_clock_lbl)
	var sp := HBoxContainer.new()
	sp.add_theme_constant_override("separation", 2)
	top.add_child(sp)
	for i in SPEEDS.size():
		var q: int = SPEEDS[i]
		var b := Kit.button(["II", "1x", "2x", "4x"][i], func(): _set_speed(q), 40, Kit.FONT_SMALL)
		b.name = "sea_speed_%d" % i
		b.custom_minimum_size.y = 34
		sp.add_child(b)
		_speed_btns.append(b)
	var lv := Kit.button("Leave", _ask_leave, 64, Kit.FONT_SMALL)
	lv.name = "sea_leave"
	lv.custom_minimum_size.y = 34
	top.add_child(lv)
	# Event messages under the top bar.
	_msg_lbl = Kit.label("", Kit.FONT_SMALL, Color.WHITE, true)
	_msg_lbl.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_msg_lbl.offset_top = 62
	_msg_lbl.offset_left = 170
	_msg_lbl.offset_right = -170
	_msg_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_msg_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_msg_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_msg_lbl.add_theme_constant_override("outline_size", 5)
	root.add_child(_msg_lbl)
	# Left: your ships.
	var sc := ScrollContainer.new()
	sc.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	sc.offset_top = 64
	sc.offset_bottom = -92
	sc.offset_left = 4
	sc.offset_right = 140
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(sc)
	_cards = VBoxContainer.new()
	_cards.add_theme_constant_override("separation", 3)
	_cards.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(_cards)
	for s in sim.n_units:
		if sim.u_side[s] == player_side:
			var card := _ship_card(s)
			_cards.add_child(card)
			_card_nodes[s] = card
	# Bottom: the selected ships' info and orders.
	var bot := VBoxContainer.new()
	bot.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bot.offset_left = 4
	bot.offset_right = -4
	bot.offset_bottom = -4
	bot.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bot.add_theme_constant_override("separation", 2)
	bot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bot)
	_info = Kit.label("", Kit.FONT_SMALL, Color.WHITE, true)
	_info.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_info.add_theme_constant_override("outline_size", 4)
	_info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bot.add_child(_info)
	_bar = HFlowContainer.new()
	_bar.add_theme_constant_override("h_separation", 3)
	_bar.add_theme_constant_override("v_separation", 3)
	_bar.alignment = FlowContainer.ALIGNMENT_CENTER
	bot.add_child(_bar)
	_end_panel = null


func _ship_card(s: int) -> Control:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", Kit.box(Color(0.08, 0.1, 0.12, 0.82), 5, 5))
	p.custom_minimum_size = Vector2(132, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 1)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(v)
	var nm := Kit.label(_card_name(s), 12, Color.WHITE)
	nm.name = "nm"
	nm.clip_text = true
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(nm)
	var bars := Control.new()
	bars.name = "bars"
	bars.custom_minimum_size = Vector2(122, 22)
	bars.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bars.draw.connect(_draw_card_bars.bind(bars, s))
	v.add_child(bars)
	p.gui_input.connect(func(e: InputEvent): _card_input(e, s))
	return p


func _card_name(s: int) -> String:
	var d: Dictionary = (scenario.get("units", []) as Array)[s]
	var t := ST.name_of(sim.s_type[s])
	if d.has("nm"):
		return "%s (%s)" % [str(d["nm"]), t]
	return t


func _draw_card_bars(c: Control, s: int) -> void:
	var w := c.size.x - 30.0
	var vals := [float(sim.s_hull[s]) / sim.s_hull0[s], float(sim.s_crew[s]) / maxi(sim.s_crew0[s], 1),
		float(sim.s_rig[s]) / maxi(sim.s_rig0[s], 1)]
	var cols := [Color(0.45, 0.85, 0.4), Color(0.6, 0.75, 1.0), Color(0.95, 0.92, 0.8)]
	for i in 3:
		var y := 1.0 + i * 6.5
		c.draw_rect(Rect2(0, y, w, 5), Color(0, 0, 0, 0.6))
		c.draw_rect(Rect2(0, y, w * clampf(vals[i], 0.0, 1.0), 5), cols[i])
	# Broadsides: port and starboard, full when loaded.
	for k in 2:
		var x := w + 6.0 + k * 11.0
		var rl := sim.s_rl[s * 2 + k]
		var full := ST.stat(sim.s_type[s], "reload") * 10 * 1000
		var f := 1.0 - float(rl) / maxi(full, 1)
		c.draw_rect(Rect2(x, 2, 8, 18), Color(0, 0, 0, 0.6))
		c.draw_rect(Rect2(x, 2 + 18 * (1.0 - f), 8, 18 * f), Color(1, 0.85, 0.4) if rl == 0 else Color(0.6, 0.55, 0.4))
	var st := sim.u_state[s]
	if st != SeaSim.S_SAIL:
		c.draw_rect(Rect2(Vector2.ZERO, c.size), Color(0, 0, 0, 0.45))


func _card_input(e: InputEvent, s: int) -> void:
	# (a touch reaches a Control as a mouse button: the project emulates it)
	var tapped := e is InputEventMouseButton and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT \
		and not (e as InputEventMouseButton).pressed
	if not tapped or sim.u_state[s] != SeaSim.S_SAIL:
		return
	if selection == [s] and _clock - _last_tap_t < DOUBLE_TAP * 2.0:
		camera.position = _pos(s)
	selection = [s]
	_last_tap_t = _clock
	_refresh_bar()


func _refresh_hud() -> void:
	var secs := sim.tick / 10
	_clock_lbl.text = "%d:%02d%s" % [secs / 60, secs % 60, "  paused" if speed_q == 0 else ""]
	for i in _speed_btns.size():
		(_speed_btns[i] as Button).modulate = Color(1, 0.85, 0.4) if SPEEDS[i] == speed_q else Color.WHITE
	var lines: Array[String] = []
	for m in _msgs:
		lines.append(str(m[0]))
	_msg_lbl.text = "\n".join(lines)
	if not _msgs.is_empty():
		_msg_lbl.add_theme_color_override("font_color", _msgs[_msgs.size() - 1][2])
	for s in _card_nodes:
		var card: Control = _card_nodes[s]
		(card.find_child("bars", true, false) as Control).queue_redraw()
		card.modulate = Color(1, 1, 1, 1) if selection.has(int(s)) else Color(0.82, 0.82, 0.82, 0.9)
	_info.text = _info_text()


func _info_text() -> String:
	var mine: Array[int] = []
	for s in selection:
		if sim.u_state[s] == SeaSim.S_SAIL:
			mine.append(s)
	if mine.is_empty():
		var f := [sim.fighting(0), sim.fighting(1)]
		return "Tap a ship of yours to command it. %s: %d fighting; the enemy: %d." % [side_names[player_side], f[player_side], f[1 - player_side]]
	if mine.size() > 1:
		return "%d ships selected. Tap the sea to sail, an enemy to engage%s." % [mine.size(), " (Board armed: tap an enemy)" if arm == "board" else ""]
	var s := mine[0]
	var mode: String = ["holding her course", "sailing to the mark", "engaging", "closing to board", "running for it", "holding a heading"][sim.s_mode[s]]
	if sim.s_grap[s] >= 0:
		mode = "grappled: boarding" if sim.s_boarder[s] != 0 else "grappled: repelling boarders"
	var sails: String = ["hove to", "battle sail", "full sail"][sim.s_sail[s]]
	var bs := ""
	for k in 2:
		var rl := sim.s_rl[s * 2 + k]
		bs += "%s %s" % [["port", "starboard"][k], ("loaded (%s)" % ST.SHOT_NAMES[sim.s_ld[s * 2 + k]].to_lower()) if rl == 0 else "%d s" % int(ceil(rl / float(maxi(sim._crew_rate(s), 1)) / 10.0))]
		if k == 0:
			bs += ", "
	var spd := sim.s_spd[s] * 10.0 / 1024.0
	return "%s: hull %d%%, crew %d, rig %d%%; %.1f kn, %s, %s; %s%s." % [_card_name(s), sim.s_hull[s] * 100 / sim.s_hull0[s],
		sim.s_crew[s], sim.s_rig[s] * 100 / maxi(sim.s_rig0[s], 1), spd * 1.94, sails, mode, bs,
		"; Board armed: tap an enemy" if arm == "board" else ""]


## The orders bar for the selection (rebuilt when the selection changes).
func _refresh_bar() -> void:
	for c in _bar.get_children():
		c.queue_free()
	var mine: Array[int] = []
	for s in selection:
		if sim.u_state[s] == SeaSim.S_SAIL and sim.u_side[s] == player_side:
			mine.append(s)
	if mine.is_empty() or not interactive:
		return
	var s0 := mine[0]
	var add := func(text: String, nm: String, on: bool, cb: Callable) -> void:
		var b := Kit.button(text, cb, 62, 12)
		b.name = nm
		b.custom_minimum_size.y = 32
		if on:
			b.modulate = Color(1, 0.85, 0.4)
		_bar.add_child(b)
	add.call("Full sail", "sea_full", sim.s_sail[s0] == 2, func(): _orders_all(SeaSim.O_SAILS, {"on": 2}))
	add.call("Battle sail", "sea_battle_sail", sim.s_sail[s0] == 1, func(): _orders_all(SeaSim.O_SAILS, {"on": 1}))
	add.call("Heave to", "sea_stop", sim.s_sail[s0] == 0, func(): _orders_all(SeaSim.O_SAILS, {"on": 0}))
	add.call("Round", "sea_round", sim.s_shot[s0] == ST.SHOT_ROUND, func(): _orders_all(SeaSim.O_SHOT, {"on": ST.SHOT_ROUND}))
	add.call("Chain", "sea_chain", sim.s_shot[s0] == ST.SHOT_CHAIN, func(): _orders_all(SeaSim.O_SHOT, {"on": ST.SHOT_CHAIN}))
	add.call("Grape", "sea_grape", sim.s_shot[s0] == ST.SHOT_GRAPE, func(): _orders_all(SeaSim.O_SHOT, {"on": ST.SHOT_GRAPE}))
	add.call("Fire at will" if sim.s_fire[s0] != 0 else "Hold fire", "sea_fire", sim.s_fire[s0] != 0,
		func(): _orders_all(SeaSim.O_FIRE, {"on": 0 if sim.s_fire[s0] != 0 else 1}))
	add.call("Board", "sea_board", arm == "board", func():
		arm = "" if arm == "board" else "board"
		_refresh_bar())
	add.call("Hold course", "sea_hold", sim.s_mode[s0] == SeaSim.M_FREE, func(): _orders_all(SeaSim.O_HOLD, {}))
	add.call("Flee", "sea_flee", sim.s_mode[s0] == SeaSim.M_FLEE, func(): _orders_all(SeaSim.O_FLEE, {}))


func _orders_all(typ: int, extra: Dictionary) -> void:
	for s in selection:
		if sim.u_side[s] != player_side or sim.u_state[s] != SeaSim.S_SAIL:
			continue
		var o := {"tick": sim.tick, "type": typ, "unit": s}
		o.merge(extra)
		order(o)
	AudioFx.click()
	# The bar shows the new setting once the order is applied (next tick).
	get_tree().create_timer(0.15).timeout.connect(_refresh_bar)


## Issue a sim order (solo: straight into the sim at its current tick).
func order(o: Dictionary) -> void:
	if not interactive or sim.decided_tick >= 0:
		return
	sim.queue_order(o)


func _set_speed(q: int) -> void:
	speed_q = q
	AudioFx.click()


func _draw_rose() -> void:
	var c := Vector2(26, 28)
	var r := 22.0
	_rose.draw_circle(c, r + 3, Color(0, 0, 0, 0.45))
	_rose.draw_arc(c, r, 0, TAU, 32, Color(1, 1, 1, 0.6), 1.5, true)
	for i in 4:
		var a := i * PI / 2.0 - PI / 2.0
		_rose.draw_line(c + Vector2(cos(a), sin(a)) * (r - 5), c + Vector2(cos(a), sin(a)) * r, Color(1, 1, 1, 0.6), 1.5)
	_rose.draw_string(ThemeDB.fallback_font, c + Vector2(-4, -r + 12), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 1, 1, 0.8))
	var wt := _wind_to()
	var tail := c - wt * (r - 4)
	var tip := c + wt * (r - 4)
	_rose.draw_line(tail, tip, Color(0.6, 0.85, 1.0), 3.0, true)
	var side := Vector2(-wt.y, wt.x)
	_rose.draw_colored_polygon(PackedVector2Array([tip + wt * 3, tip - wt * 8 + side * 6, tip - wt * 8 - side * 6]), Color(0.6, 0.85, 1.0))
	var brg := SeaSim.angle_to_bearing(sim.w_from)
	var names := ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
	var nm: String = names[int(round(brg / 45.0)) % 8]
	var force := "light" if sim.w_str < 40 else "moderate" if sim.w_str < 65 else "fresh" if sim.w_str < 85 else "strong"
	_rose.draw_string(ThemeDB.fallback_font, Vector2(54, 22), "Wind from %s" % nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.WHITE)
	_rose.draw_string(ThemeDB.fallback_font, Vector2(54, 40), "%s breeze" % force, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.8, 0.85, 0.9))


# ------------------------------------------------------------- the ending ---

func _show_end() -> void:
	_end_shown = true
	var won := sim.winner == player_side
	var p := Kit.panel(Color(0.08, 0.1, 0.12, 0.94), 14)
	p.set_anchors_preset(Control.PRESET_CENTER)
	p.grow_horizontal = Control.GROW_DIRECTION_BOTH
	p.grow_vertical = Control.GROW_DIRECTION_BOTH
	var v := Kit.vbox(8)
	p.add_child(v)
	v.add_child(Kit.label("VICTORY" if won else "DEFEAT", 24, Kit.COL_GOOD if won else Kit.COL_BAD))
	var r := sim.result()
	for sd in [player_side, 1 - player_side]:
		var t: Dictionary = r["sides"][sd]
		v.add_child(Kit.label("%s: %d ships, %d still fighting, %d sunk, %d taken, %d escaped; crews %d of %d." % [
			side_names[sd], int(t["ships"]), int(t["fighting"]), int(t["sunk"]), int(t["taken"]), int(t["fled"]),
			int(t["crew"]), int(t["crew0"])], Kit.FONT_SMALL, Color.WHITE, true))
	var b := Kit.button("Continue", func(): exit_requested.emit(), 140)
	b.name = "sea_continue"
	v.add_child(b)
	p.custom_minimum_size = Vector2(minf(520.0, get_viewport_rect().size.x - 40.0), 0)
	_hud.add_child(p)
	_end_panel = p
	AudioFx.play("horn_victory" if won else "horn_defeat", 0.9, 0.0, "horn")


func _ask_leave() -> void:
	if sim.decided_tick >= 0:
		exit_requested.emit()
		return
	if _leave_dlg != null:
		return
	var p := Kit.panel(Color(0.08, 0.1, 0.12, 0.95), 14)
	p.set_anchors_preset(Control.PRESET_CENTER)
	p.grow_horizontal = Control.GROW_DIRECTION_BOTH
	p.grow_vertical = Control.GROW_DIRECTION_BOTH
	var v := Kit.vbox(8)
	p.add_child(v)
	v.add_child(Kit.label("Leave the battle? It counts as lost: your ships still fighting make their escape, the struck are taken.",
		Kit.FONT, Color.WHITE, true))
	var h := Kit.hbox(8)
	h.add_child(Kit.button("Leave", func(): exit_requested.emit(), 100))
	h.add_child(Kit.button("Stay", func():
		_leave_dlg.queue_free()
		_leave_dlg = null, 100))
	v.add_child(h)
	p.custom_minimum_size = Vector2(minf(460.0, get_viewport_rect().size.x - 40.0), 0)
	_hud.add_child(p)
	_leave_dlg = p


# ------------------------------------------------------------------ input ---

func _frame_fleet() -> void:
	var vp := get_viewport_rect().size
	var fit := minf(vp.x / sim.field_w, vp.y / sim.field_h)
	camera.zoom = Vector2.ONE * clampf(fit * 1.6, ZOOM_MIN, ZOOM_MAX)
	var c := Vector2.ZERO
	var n := 0
	for s in sim.n_units:
		c += _pos(s)
		n += 1
	camera.position = c / maxi(n, 1)
	_clamp_cam()


func _clamp_cam() -> void:
	var m := 300.0
	camera.position = camera.position.clamp(Vector2(-m, -m), Vector2(sim.field_w + m, sim.field_h + m))


func _world(screen: Vector2) -> Vector2:
	return get_canvas_transform().affine_inverse() * screen


func _zoom_at(screen: Vector2, f: float) -> void:
	var before := _world(screen)
	camera.zoom = Vector2.ONE * clampf(camera.zoom.x * f, ZOOM_MIN, ZOOM_MAX)
	camera.force_update_scroll()
	var after := _world(screen)
	camera.position += before - after
	_clamp_cam()


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventMouseButton:
		var mb := e as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_at(mb.position, 1.12)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_at(mb.position, 1.0 / 1.12)
		return
	if e is InputEventKey and (e as InputEventKey).pressed:
		match (e as InputEventKey).keycode:
			KEY_SPACE:
				_set_speed(0 if speed_q != 0 else 4)
			KEY_1:
				_set_speed(4)
			KEY_2:
				_set_speed(8)
			KEY_3:
				_set_speed(16)
			KEY_ESCAPE:
				selection.clear()
				arm = ""
				_refresh_bar()
		return
	if e is InputEventScreenTouch:
		var t := e as InputEventScreenTouch
		if t.pressed:
			_touch[t.index] = t.position
			if _touch.size() == 1:
				_press_pos = t.position
				_press_t = _clock
				_dragging = false
				_boxing = false
			elif _touch.size() == 2:
				var ps: Array = _touch.values()
				_pinch_d = (ps[0] as Vector2).distance_to(ps[1])
				_boxing = false
		else:
			var was := _touch.size()
			_touch.erase(t.index)
			if was == 1:
				if _boxing:
					_box_select()
				elif not _dragging:
					_tap(t.position)
				_boxing = false
				_dragging = false
	elif e is InputEventScreenDrag:
		var d := e as InputEventScreenDrag
		var prev: Vector2 = _touch.get(d.index, d.position)
		_touch[d.index] = d.position
		if _touch.size() >= 2:
			var ps2: Array = _touch.values()
			var nd := (ps2[0] as Vector2).distance_to(ps2[1])
			var mid := ((ps2[0] as Vector2) + (ps2[1] as Vector2)) * 0.5
			if _pinch_d > 1.0:
				_zoom_at(mid, nd / _pinch_d)
			_pinch_d = nd
			camera.position -= (d.position - prev) / camera.zoom.x * 0.5
			_dragging = true
			_clamp_cam()
			return
		if not _dragging and not _boxing and d.position.distance_to(_press_pos) > DRAG_PX:
			if _clock - _press_t >= LONG_PRESS:
				_boxing = true
				_box_a = _world(_press_pos)
			else:
				_dragging = true
		if _boxing:
			_box_b = _world(d.position)
		elif _dragging:
			camera.position -= (d.position - prev) / camera.zoom.x
			_clamp_cam()


func _ship_at(w: Vector2) -> int:
	var best := -1
	var bd := 1e9
	var pick := 22.0 / camera.zoom.x
	for s in sim.n_units:
		var st := sim.u_state[s]
		if st == SeaSim.S_SUNK or st == SeaSim.S_FLED:
			continue
		var r := maxf(ST.stat(sim.s_type[s], "len") * 0.6 * VIS, pick)
		var d := _pos(s).distance_to(w)
		if d < r and d < bd:
			bd = d
			best = s
	return best


func _tap(screen: Vector2) -> void:
	if not interactive:
		return
	var w := _world(screen)
	var s := _ship_at(w)
	var double := _clock - _last_tap_t < DOUBLE_TAP and s == _last_tap_ship
	_last_tap_t = _clock
	_last_tap_ship = s
	if s >= 0 and sim.u_side[s] == player_side:
		if sim.u_state[s] != SeaSim.S_SAIL:
			return
		if double:
			selection.clear()
			for k in sim.n_units:
				if sim.u_side[k] == player_side and sim.u_state[k] == SeaSim.S_SAIL:
					selection.append(k)
		else:
			selection = [s]
		arm = ""
		AudioFx.click()
		_refresh_bar()
		return
	var mine: Array[int] = []
	for k in selection:
		if sim.u_side[k] == player_side and sim.u_state[k] == SeaSim.S_SAIL:
			mine.append(k)
	if mine.is_empty():
		return
	if s >= 0:
		# An enemy: engage her, or board her when Board is armed.
		var typ := SeaSim.O_BOARD if arm == "board" else SeaSim.O_TARGET
		if sim.u_state[s] == SeaSim.S_STRUCK:
			typ = SeaSim.O_BOARD  # a struck ship is taken by laying her alongside
		for k in mine:
			order({"tick": sim.tick, "type": typ, "unit": k, "target": s})
		arm = ""
		_fx.append(["flash", _pos(s), 0.0, 0, 0])
		AudioFx.play("order_ok", 0.6, 0.0, "ui")
		get_tree().create_timer(0.15).timeout.connect(_refresh_bar)
		return
	arm = ""
	# The sea: sail there, several ships in a line abreast across the way.
	var c := Vector2.ZERO
	for k in mine:
		c += _pos(k)
	c /= mine.size()
	var dir := (w - c).normalized() if w.distance_to(c) > 1.0 else Vector2.RIGHT
	var across := Vector2(-dir.y, dir.x)
	for i in mine.size():
		var off := (i - (mine.size() - 1) * 0.5) * 70.0
		var g := w + across * off
		g = g.clamp(Vector2(20, 20), Vector2(sim.field_w - 20, sim.field_h - 20))
		order({"tick": sim.tick, "type": SeaSim.O_SAIL, "unit": mine[i], "x": int(g.x), "y": int(g.y)})
	AudioFx.play("order_ok", 0.6, 0.0, "ui")
	get_tree().create_timer(0.15).timeout.connect(_refresh_bar)


func _box_select() -> void:
	var r := Rect2(_box_a, _box_b - _box_a).abs()
	var got: Array[int] = []
	for s in sim.n_units:
		if sim.u_side[s] == player_side and sim.u_state[s] == SeaSim.S_SAIL and r.has_point(_pos(s)):
			got.append(s)
	if not got.is_empty():
		selection = got
		arm = ""
		_refresh_bar()
