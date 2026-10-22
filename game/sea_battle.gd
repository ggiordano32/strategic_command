extends Node2D
## The real-time sea battle screen (N3a; docs/DESIGN.md "Sea battles (as
## built, N3a)"). View only: it runs sim/sea_sim.gd at 10 ticks a second
## (pause, 1x, 2x, 4x), draws it interpolated between ticks and turns taps
## into sim orders (solo: queued with the sim's own tick).
##
## Live co-op at sea (`coop`, game/net/coop_session.gd, as the land battle
## view does it): the session's lockstep runs the SeaSim (this view rebinds
## to it when it starts or restores a snapshot); orders go through
## coop.issue() for the ships this player commands only (a tap on a
## team-mate's ship says whose it is); II and the speeds are votes; Gift
## hands the selected ships to a team-mate (the picker when there are
## several); the card column marks whose each ship is; the co-op HUD
## (game/coop_hud.gd: the roster strip, the lobby, waiting / resync status,
## vote chips, Continue without a disconnected player) sits over it;
## Continue at the end waits for the final frame; coop_exit_result() is what
## the campaign screen uploads (the host once; the last player's forfeit).
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
## (the land battle's gun-smoke look), shot splashes and splinters, fires
## by their intensity, the magazine blast, sinking and wreckage, grapples.
##
## N3b deck melee: while ships are grappled an inset (top right; a tap
## centres the pair) shows the two decks side by side in the diorama look:
## planking, rails, masts, grapnel lines, the crews as little groups of men
## in their ship's colour (the captain gilded), cold-steel sparks, pistol and
## musket smoke, each side's men and heart; the clash and volleys play
## through the audio hooks; the outcome (taken / thrown back / both spent)
## stays a moment. N3c fire ships: a tarred hull with brushwood on deck;
## lit, she blazes from end to end under a black column, her crew pull away
## in the boat, and what she grapples catches; "Light her" in the bar, and
## a tap on an enemy sends her in.

signal exit_requested

const SeaSim := preload("res://sim/sea_sim.gd")
const ST := preload("res://sim/sea_types.gd")
const FM := preload("res://sim/fixed_math.gd")
const Kit := preload("res://game/campaign/ui_kit.gd")
const BTheme := preload("res://game/battle_theme.gd")
const SeaKey := preload("res://game/sea_key.gd")
const CData := preload("res://campaign/cdata.gd")
const AudioFx := preload("res://game/audio.gd")
const CoopHud := preload("res://game/coop_hud.gd")
const SeaBook := preload("res://game/sea_book.gd")
const Lockstep := preload("res://sim/lockstep.gd")

const TICK_SEC := 0.1
const MAX_STEPS := 4
const ZOOM_MIN := 0.12
const ZOOM_MAX := 3.0
const DRAG_PX := 16.0
const LONG_PRESS := 0.35
const DOUBLE_TAP := 0.35
const GunSmoke := preload("res://game/gun_smoke.gd")
const BattleLook := preload("res://game/battle_look.gd")
const SeaLook := preload("res://game/sea_look.gd")
const COL_SEA := Color(0.13, 0.36, 0.5)
const COL_SEA_DEEP := Color(0.09, 0.27, 0.4)
const COL_SAIL := Color(0.96, 0.94, 0.86)
const COL_HULL := Color(0.42, 0.27, 0.16)
const COL_DECK := Color(0.68, 0.55, 0.37)
const SIDE_COLS := [Color(0.25, 0.55, 0.95), Color(0.9, 0.3, 0.25)]
const SPEEDS := [0, 4, 8, 16]   # quarter steps: pause, 1x, 2x, 4x
const VIS := 1.5                 # ships drawn this much larger than their length (to read on a phone)

# ---- set by whoever opens it ----
var scenario: Dictionary = {}
var seed_value := 1
var player_side := 0
var campaign_mode := false
var title_text := "Sea battle"
var side_names := ["Your fleet", "The enemy"]
var side_cols: Array = SIDE_COLS.duplicate()
var coop = null              # live co-op: game/net/coop_session.gd (null: solo)
var coop_hud = null
var coop_region := ""
var look_cell := Vector2i(-1, -1)   # the campaign cell of the battle (the look: bathymetry, harbour fort); (-1, -1): none
var look_region := -1               # ... and its nearest region
var _look: SeaLook
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
var _gs := GunSmoke.new()  # broadside banks and haze (game/gun_smoke.gd), cap 420
var _fx: Array = []                # [kind, pos, age, a, b]: "splash", "hit", "flash", "blast", "shot", "debris"
var _msgs: Array = []              # [text, age, color]

# nodes
var camera: Camera2D
var _water: Node2D
var _land: Node2D
var _props: Node2D
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
var _speed_seg: Kit.Segmented = null   # the speed capsule (lit: the speed in force)
var _speed_lit := -1
var _key_btn: Button = null
var _key_panel: PanelContainer = null
var _end_panel: PanelContainer
var _leave_dlg: PanelContainer
var _card_nodes := {}
var _inset: Control                # the deck melee inset (N3b)
var _inset_m := -1                 # the boarder (melee slot) shown
var _inset_end := ""               # the outcome shown after it ends
var _inset_end_t := -10.0
var _inset_t := -1                 # the target of the melee shown
var _dk_pos := {}                  # figure -> Vector2 drawn (cells, eased toward the sim's)
var _dk_smoke: Array = []          # [cell pos, age, size]
var _clash_t := 0.0

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
var _calpha := 1.0                 # co-op: interpolation between the last two ticks
var _hud_shim = null
var _sc: ScrollContainer = null
var _cont_btn: Button = null
# order help (tooltips, the long-press card, the hint line) and the Ship book
var book: SeaBook = null
var _book_btn: Button = null
var _book_resume := -1             # solo: the speed to go back to when the book closes
var _hint_lbl: Label = null
var _hint_t := 0.0
var _help_card: PanelContainer = null
var _help_catch: Control = null
var _lp_token := 0                 # long press on an order button: the press being timed
var _lp_swallow := false           # ... fired, so the release is not a tap
var _pct_shown := {}               # sail setting -> clock when its speed % first showed in the status line
var _bar_fire := 0                 # (Douse) the selection's burning / dousing bits the bar was built for
var input_counts := {}             # telemetry counters of this battle's inputs ("douse")
const LONG_HELP := 0.5
const HINT_SEC := 3.0
const PCT_SEC := 6.0


## What game/coop_hud.gd needs of a HUD (the land Hud's names).
class HudShim:
	extends RefCounted
	var pause_button: Control
	var speed_button: Control
	var speed_panel: Control
	var bottom_px := 96.0

	func add_ui_control(_c: Control) -> void:
		pass  # (its panels stop touches themselves)

	func bottom_height() -> float:
		return bottom_px


func _ready() -> void:
	_gs.cap = 420
	sim = SeaSim.new()
	sim.setup(scenario, seed_value)
	var n := sim.n_units
	_px.resize(n)
	_py.resize(n)
	_ph.resize(n)
	for s in n:
		_wake.append(PackedVector2Array())
	_snap_prev()
	_look = SeaLook.new()
	_look.setup(sim, seed_value, scenario, look_cell, look_region)
	_water = Node2D.new()
	_water.draw.connect(_draw_water)
	_water.material = _look.water_mat
	add_child(_water)
	_land = Node2D.new()
	_land.draw.connect(_draw_land)
	_land.material = _look.land_mat
	add_child(_land)
	_props = Node2D.new()
	_props.draw.connect(_look.draw_props.bind(_props))
	add_child(_props)
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
		if sim.u_side[s] == player_side and _mine(s):
			selection.append(s)
			break
	if coop != null:
		_coop_ready()
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
	if coop != null:
		_coop_step(delta)
	else:
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
	_inset_tick(delta)
	if sim.decided_tick >= 0 and _decided_at < 0.0:
		_decided_at = _clock
	if _decided_at >= 0.0 and not _end_shown and _clock - _decided_at > 3.5:
		_show_end()
	_look.tick(_clock, sim)
	_ships.queue_redraw()
	_sky.queue_redraw()
	_rose.queue_redraw()
	_refresh_hud()


func _alpha() -> float:
	if coop != null:
		return _calpha
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
			SeaSim.EV_DECK_SHOT:
				if a == _inset_m:
					var fi := a * SeaSim.FIG + sim.ev_b[i]
					_dk_smoke.append([Vector2(sim.f_x[fi], sim.f_y[fi]), 0.0, 0.5 + 0.12 * mini(sim.f_n[fi], 6)])
				AudioFx.play("musket", 0.45, 0.0, "volley")
			SeaSim.EV_CAPTAIN:
				var who := a if sim.ev_b[i] == 0 else c
				_msg("The captain of %s falls!" % _name(who), Color(1, 0.8, 0.5))
			SeaSim.EV_DECK_END:
				var res: String = ["", "The deck of %s is taken!" % _name(c), "%s's boarders are thrown back." % _name(a),
					"Both crews are spent: %s and %s cut loose." % [_name(a), _name(c)]][clampi(sim.ev_d[i], 0, 3)]
				if a == _inset_m:
					_inset_end = res.substr(0, 1).to_upper() + res.substr(1)
					_inset_end_t = _clock
				AudioFx.play("unit_break" if sim.ev_d[i] != 1 else "horn_victory", 0.5, 0.0, "state")
			SeaSim.EV_LIT:
				_msg("%s is fired and sent in!" % _name(a), Color(1, 0.5, 0.2))
				AudioFx.play("burst", 0.6, 0.0, "art")
			SeaSim.EV_ABANDON:
				_msg("Her crew take to the boat.", Color(0.9, 0.85, 0.75))
				_fx.append(["boat", _pos(a), 0.0, a, int(sim.heading(a))])
			SeaSim.EV_FS_CONTACT:
				_msg("The fire ship grapples %s: she is ablaze!" % _name(c), Color(1, 0.45, 0.2))
				AudioFx.play("burst", 0.8, 0.0, "art")


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
		_puff(at + sd * 4.0, 3.2 + guns * 0.07, sd)
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


func _puff(at: Vector2, sz: float, d: Vector2) -> void:
	_gs.add(at, d, sz * 1.5, sz * 3.5)
	_gs.feed_haze(at, 160.0, 0.05)


func _age_fx(delta: float) -> void:
	var dt := delta * maxf(speed_q / 4.0, 0.0) if speed_q > 0 else 0.0
	_gs.tick(dt, _wind_to() * (2.0 + sim.w_str * 0.03))
	var keep: Array = []
	for f in _fx:
		f[2] = float(f[2]) + dt
		var life := 1.2
		match str(f[0]):
			"blast":
				life = 3.0
			"debris":
				life = 14.0
			"boat":
				life = 24.0
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
	if col.get_luminance() < 0.35:
		col = col.lightened(0.55)  # (a dark faction colour reads on the sea)
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

## The water: one rect over the field and a margin, the whole look in game/sea_water.gdshader
## (drawn once; the shader's uniforms move with SeaLook.tick).
func _draw_water() -> void:
	_water.draw_rect(Rect2(-2000, -2000, float(sim.field_w) + 4000.0, float(sim.field_h) + 4000.0), Color.WHITE)


## The land: one rect over the sim's grid and a margin (the coast goes on past the field), game/sea_land.gdshader.
func _draw_land() -> void:
	_land.draw_rect(Rect2(-900, -900, float(sim.g_w * SeaSim.CELL_M) + 1800.0, float(sim.g_h * SeaSim.CELL_M) + 1800.0), Color.WHITE)


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
		_look.draw_wake(_ships, pts, bm, clampf(float(sim.s_spd[s]) / maxf(float(ST.stat(sim.s_type[s], "vmax")) * 10.24, 1.0), 0.0, 1.0), _head(s))
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
			"boat":
				# The fire ship's crew pulling away from their blazing ship.
				var bh := float(int(f[4])) * TAU / 1024.0 + PI * 0.75
				var bf := Vector2(cos(bh), sin(bh))
				var bp: Vector2 = Vector2(f[1]) + bf * (10.0 + age * 3.2)
				var bsd := Vector2(-bf.y, bf.x)
				var ba := clampf(1.0 - age / 24.0, 0.0, 1.0)
				var boat := PackedVector2Array([bp + bf * 4.5, bp + bsd * 1.6, bp - bf * 3.5 + bsd * 1.3, bp - bf * 3.5 - bsd * 1.3,
					bp - bsd * 1.6])
				_ships.draw_colored_polygon(boat, Color(0.4, 0.27, 0.16, ba))
				var stroke := sin(_clock * 5.0) * 1.5
				for sg in [-1.0, 1.0]:
					_ships.draw_line(bp + bsd * 1.4 * sg, bp + bsd * 4.0 * sg + bf * stroke, Color(0.3, 0.2, 0.1, 0.8 * ba), 0.6)
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
				_ships.draw_line(a + off, b - off, SeaKey.col("grapple", Color.WHITE, 0.95), 1.4 * lw + 0.6)
			var mid := (a + b) * 0.5
			var rad := a.distance_to(b) * 0.5 + float(ST.stat(sim.s_type[s], "len")) * VIS * 0.55
			_ships.draw_arc(mid, rad + 2.0 * sin(_clock * 5.0), 0, TAU, 36, SeaKey.col("board", Color.WHITE, 0.85), 2.5 * lw, true)
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
	var fire := ST.is_fire(ty)
	var lit := fire and sim.s_lit[s] >= 0
	_ships.draw_colored_polygon(world, Color(COL_HULL.darkened(0.55 if fire else 0.0), fade))
	var deck := PackedVector2Array()
	for v in hull:
		deck.append(xf * (v * 0.78 * shrink))
	var dc := COL_DECK.darkened(0.15 if st != SeaSim.S_SAIL else 0.0)
	if fire:
		dc = Color(0.22, 0.17, 0.12) if lit else Color(0.36, 0.3, 0.22)  # tarred, then charred
	_ships.draw_colored_polygon(deck, Color(dc, fade))
	if fire and not lit and sink == 0.0:
		# Brushwood, tar barrels and brimstone stacked on deck.
		for k in 6:
			var bpos: Vector2 = xf * Vector2((float(k) / 5.0 - 0.5) * ln * 0.6, (0.18 if k % 2 == 0 else -0.18) * bm)
			_ships.draw_circle(bpos, bm * 0.13, Color(0.55, 0.42, 0.2) if k % 3 != 0 else Color(0.25, 0.2, 0.15))
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
	# Fire aboard, by its intensity (a lit fire ship from end to end).
	if sim.s_burn[s] > 0:
		var lv := clampf(float(sim.s_burn[s]) / SeaSim.FIRE_MAX, 0.05, 1.0)
		var nfl := 3 + int(lv * 9.0)
		var wt2 := _wind_to()
		var wp := Vector2(-wt2.y, wt2.x)
		for k in nfl:
			var fpos: Vector2 = xf * Vector2((sin(k * 1.7 + s) * (0.15 + 0.3 * lv)) * ln, cos(k * 2.3) * bm * 0.3)
			var fl2 := (2.0 + 2.5 * absf(sin(_clock * 11.0 + k))) * (0.7 + lv * 0.9)
			# A tongue of flame leaning downwind, flickering; a hot core.
			var lean := wt2 * fl2 * (1.6 + 0.6 * sin(_clock * 13.0 + k * 2.0)) + wp * fl2 * 0.35 * sin(_clock * 9.0 + k)
			var tongue := PackedVector2Array([fpos - wp * fl2 * 0.8, fpos - wt2 * fl2 * 0.5, fpos + wp * fl2 * 0.8, fpos + lean])
			_ships.draw_colored_polygon(tongue, Color(1.0, 0.35 + 0.25 * absf(sin(_clock * 7.0 + k)), 0.08, 0.85))
			var core := PackedVector2Array([fpos - wp * fl2 * 0.4, fpos - wt2 * fl2 * 0.25, fpos + wp * fl2 * 0.4, fpos + lean * 0.55])
			_ships.draw_colored_polygon(core, Color(1.0, 0.85, 0.4, 0.9))
		if lv > 0.3:
			# Embers blowing off downwind.
			for k2 in int(lv * 8.0):
				var ph := fposmod(_clock * 0.9 + k2 * 0.37 + s * 0.13, 1.0)
				var ep: Vector2 = p + wt2 * (ph * ln * 1.4) + wp * sin(k2 * 2.1 + _clock) * bm * 0.8
				_ships.draw_circle(ep, 0.6 + (1.0 - ph) * 0.8, Color(1.0, 0.7, 0.3, 0.9 * (1.0 - ph)))
	# Selection ring and a small health bar for every ship.
	if selection.has(s):
		_ships.draw_arc(p, ln * 0.62 + 4.0, 0, TAU, 32, SeaKey.col("selected", _side_col(sim.u_side[s]), 0.95), 2.0 * lw, true)
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
				var flag := _side_col(sim.u_side[s])
				for i in range(1, pts.size()):
					_dashed(pts[i - 1], pts[i], SeaKey.col("course", flag, al), 1.6 * lw, 10.0 * lw)
				_ships.draw_arc(g, 9.0 * lw + 3.0, 0, TAU, 20, SeaKey.col("waypoint", flag, al), 1.6 * lw)
				if pts.size() > 2:
					_ships.draw_circle(pts[1], 3.0 * lw + 1.0, SeaKey.col("course", flag, al))
			SeaSim.M_ENGAGE, SeaSim.M_BOARD:
				var t := sim.s_tgt[s]
				if t >= 0:
					var tp := _pos(t)
					var c := SeaKey.col("attack" if sim.s_mode[s] == SeaSim.M_ENGAGE else "board", Color.WHITE, al)
					_dashed(p, tp, c, 1.6 * lw, 8.0 * lw)
					var tl := float(ST.stat(sim.s_type[t], "len")) * VIS
					_ships.draw_arc(tp, tl * 0.62 + 6.0, 0, TAU, 28, c, 2.0 * lw, true)
			SeaSim.M_FIRE:
				var tf := sim.s_tgt[s]
				if tf >= 0:
					var tpf := _pos(tf)
					var cf := SeaKey.col("fire", Color.WHITE, al)
					_dashed(p, tpf, cf, 2.0 * lw, 6.0 * lw)
					_ships.draw_arc(tpf, float(ST.stat(sim.s_type[tf], "len")) * VIS * 0.62 + 8.0, 0, TAU, 28, cf, 2.4 * lw, true)
					if sim.s_lit[s] < 0:
						_ships.draw_arc(p, float(SeaSim.FS_LIGHT_M), 0, TAU, 48, SeaKey.col("fire", Color.WHITE, al * 0.25), 1.2 * lw)
			SeaSim.M_FLEE:
				var fpts := course_points(s)
				for i in range(1, fpts.size()):
					_dashed(fpts[i - 1], fpts[i], SeaKey.col("flee", Color.WHITE, al * 0.8), 1.4 * lw, 6.0 * lw)
		if sel:
			# The broadsides' arcs and reach, loaded (white) or reloading (dim).
			var h := sim.heading(s)
			for k in 2:
				var ctr := ((h - 256) if k == 0 else (h + 256)) * TAU / 1024.0
				var rng := float(sim.shot_range(s, sim.s_ld[s * 2 + k]))
				var half := SeaSim.ARC * TAU / 1024.0
				var loaded := sim.s_rl[s * 2 + k] == 0
				var ac := SeaKey.col("arcs", Color.WHITE, 0.4 if loaded else 0.12)
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
	_gs.draw(_sky, drift, _view_rect().grow(60.0), 120.0, BattleLook.is_diorama())
	# Smoke columns over burning ships.
	for s in sim.n_units:
		if sim.s_burn[s] > 0 and sim.u_state[s] != SeaSim.S_SUNK:
			var p2 := _pos(s)
			var lv := clampf(float(sim.s_burn[s]) / SeaSim.FIRE_MAX, 0.1, 1.0)
			var np := 4 + int(lv * 8.0)
			for k in np:
				var t := fposmod(_clock * 0.35 + float(k) / np, 1.0)
				var c := p2 + drift * t * (10.0 + 18.0 * lv) + Vector2(sin(k * 1.3 + _clock), 0) * 3.0
				_sky.draw_circle(c, (4.0 + t * 16.0) * (0.7 + lv * 0.9), Color(0.16, 0.14, 0.13, (0.35 + 0.3 * lv) * sin(PI * t)))
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
	var desk := BTheme.desktop(get_viewport_rect().size.x)
	if desk:
		var em := Kit.emblem(CData.pack, 40.0)
		em.name = "bar_emblem"
		em.mouse_filter = Control.MOUSE_FILTER_IGNORE
		em.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		top.add_child(em)
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
	# Desktop: the setting's emblem at the left of the bar and the title in the title face (18); phones as before.
	var tl: Label = Kit.title(title_text, 18) if desk else Kit.label(title_text, Kit.FONT_SMALL, Kit.COL_GOLD)
	tl.name = "sea_title"
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	tl.clip_text = true
	tl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mid.add_child(tl)
	_clock_lbl = Kit.label("0:00", Kit.FONT_SMALL, Color.WHITE)
	_clock_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_clock_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mid.add_child(_clock_lbl)
	# The speeds: one capsule (II 1x 2x 4x, the one in force lit); each press acts, even on the lit one (II toggles).
	_speed_lit = SPEEDS.find(speed_q)
	_speed_seg = BTheme.capsule([["II", 0], ["1x", 1], ["2x", 2], ["4x", 3]], func(i: int): _on_speed(SPEEDS[i]), "sea_speed",
		Kit.FONT_SMALL, 40.0, 34.0, _speed_lit)
	var stips := [["Pause", "Hold the battle (the guns and the wind stop)."], ["Normal speed", "Real time."], ["Twice as fast", "2x."],
		["Four times as fast", "4x, to close a long chase."]]
	for i in SPEEDS.size():
		var sb: Button = _speed_seg.buttons()[i]
		Kit.tip(sb, stips[i][0], stips[i][1])
		_speed_btns.append(sb)
	top.add_child(_speed_seg)
	_book_btn = Kit.icon_button("Ships", "units", _open_book, 64, Kit.FONT_SMALL)
	_book_btn.name = "sea_book_button"
	Kit.tip(_book_btn, "Ship book", "Points of sail, sails, shot, boarding and every ship's numbers.")
	_book_btn.custom_minimum_size.y = 34
	BTheme.plate(_book_btn, false, false, false)
	top.add_child(_book_btn)
	_key_btn = Kit.icon_button("Key", "key", func(): _set_key(_key_panel == null or not _key_panel.visible), 60, Kit.FONT_SMALL)
	_key_btn.name = "sea_key_button"
	Kit.tip(_key_btn, "Key", "What each line and marker on the water means.")
	_key_btn.custom_minimum_size.y = 34
	BTheme.plate(_key_btn, false, false, false)
	top.add_child(_key_btn)
	var lv := Kit.button("Leave", _ask_leave, 64, Kit.FONT_SMALL)
	lv.name = "sea_leave"
	Kit.tip(lv, "Leave", "Withdraw from the battle. It counts as lost.")
	lv.custom_minimum_size.y = 34
	BTheme.plate(lv, false, false, false)
	top.add_child(lv)
	var brule := BTheme.bar_rule()
	brule.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	brule.offset_top = 62.0
	brule.offset_bottom = 63.0
	root.add_child(brule)
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
	# (N3b) The deck melee inset, top right.
	_inset = Control.new()
	_inset.name = "sea_deck_inset"
	_inset.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_inset.mouse_filter = Control.MOUSE_FILTER_STOP
	_inset.visible = false
	_inset.draw.connect(_draw_inset)
	_inset.gui_input.connect(_inset_input)
	root.add_child(_inset)
	# Left: your ships.
	var sc := ScrollContainer.new()
	_sc = sc
	sc.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	sc.offset_top = 64 if coop == null else 92  # (co-op: the roster strip above)
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
	_hint_lbl = Kit.label("", Kit.FONT_SMALL, Color(0.85, 0.92, 1.0), true)
	_hint_lbl.name = "sea_hint"
	_hint_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_hint_lbl.add_theme_constant_override("outline_size", 4)
	_hint_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint_lbl.visible = false
	_bar = HFlowContainer.new()
	_bar.add_theme_constant_override("h_separation", 3)
	_bar.add_theme_constant_override("v_separation", 3)
	_bar.alignment = FlowContainer.ALIGNMENT_CENTER
	bot.add_child(_bar)
	bot.add_child(_hint_lbl)  # (under the row)
	_key_panel = SeaKey.KeyPanel.new(_side_col(player_side))
	_key_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_key_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_key_panel.offset_top = 68.0
	_key_panel.offset_right = -6.0
	_key_panel.offset_left = -6.0 - minf(340.0, get_viewport_rect().size.x - 12.0)
	_key_panel.offset_bottom = 68.0 + minf(420.0, get_viewport_rect().size.y - 160.0)
	_key_panel.toggled.connect(_set_key)
	_key_panel.visible = SeaKey.load_pref()
	root.add_child(_key_panel)
	if not _key_panel.visible and not SeaKey.hinted:
		SeaKey.hinted = true
		_show_hint("Not sure what a line means? Tap Key, top right.")
	book = SeaBook.new()
	book.closed.connect(_book_closed)
	root.add_child(book)
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
	# Broadsides: port and starboard, full when loaded (none on a fire ship).
	for k in (0 if ST.is_fire(sim.s_type[s]) else 2):
		var x := w + 6.0 + k * 11.0
		var rl := sim.s_rl[s * 2 + k]
		var full := ST.stat(sim.s_type[s], "reload") * 10 * 1000
		var f := 1.0 - float(rl) / maxi(full, 1)
		c.draw_rect(Rect2(x, 2, 8, 18), Color(0, 0, 0, 0.6))
		c.draw_rect(Rect2(x, 2 + 18 * (1.0 - f), 8, 18 * f), Color(1, 0.85, 0.4) if rl == 0 else Color(0.6, 0.55, 0.4))
	var st := sim.u_state[s]
	if st != SeaSim.S_SAIL:
		c.draw_rect(Rect2(Vector2.ZERO, c.size), Color(0, 0, 0, 0.45))
	# Live co-op: whose ship this is (a band in the commander's colour once
	# another player takes part on this side).
	if coop != null and coop.ls != null and not coop.teammates_in(coop.me).is_empty():
		var cmd: int = coop.ls.commander(s)
		c.draw_rect(Rect2(c.size.x - 4.0, 0, 4.0, c.size.y), coop.player_color(cmd) if cmd >= 0 else Color(0.5, 0.5, 0.5))


func _card_input(e: InputEvent, s: int) -> void:
	# (a touch reaches a Control as a mouse button: the project emulates it)
	var tapped := e is InputEventMouseButton and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT \
		and not (e as InputEventMouseButton).pressed
	if not tapped or sim.u_state[s] != SeaSim.S_SAIL:
		return
	if not _mine(s):
		_not_mine_hint(s)
		return
	if selection == [s] and _clock - _last_tap_t < DOUBLE_TAP * 2.0:
		camera.position = _pos(s)
	selection = [s]
	_last_tap_t = _clock
	_refresh_bar()


## The Key panel open or closed (remembered in settings).
func _set_key(on: bool) -> void:
	_key_panel.visible = on
	SeaKey.save_pref(on)
	_count("key_open" if on else "key_close")


## The speed capsule's lit segment (restyled only when it changes).
func _light_speed(i: int) -> void:
	if _speed_seg == null or i == _speed_lit:
		return
	_speed_lit = i
	_speed_seg.set_value(i)
	for b in _speed_seg.buttons():
		BTheme.trim_margins(b, 6.0)


func _refresh_hud() -> void:
	var secs := sim.tick / 10
	_clock_lbl.text = "%d:%02d%s" % [secs / 60, secs % 60, "  paused" if speed_q == 0 else ""]
	_light_speed(SPEEDS.find(speed_q))
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
		if not _mine(int(s)):
			card.modulate = Color(0.7, 0.7, 0.7, 0.75)
	_info.text = _info_text()
	# (Douse) The bar shows Douse only while a selected ship burns: rebuild it when that changes.
	var fk := _bar_fire_key()
	if fk != _bar_fire:
		_bar_fire = fk
		_refresh_bar()
	if _hint_lbl.visible and _clock - _hint_t > HINT_SEC:
		_hint_lbl.visible = false
	if coop != null:
		_coop_hud_tick()


func _info_text() -> String:
	var mine: Array[int] = []
	for s in selection:
		if sim.u_state[s] == SeaSim.S_SAIL:
			mine.append(s)
	if mine.is_empty():
		var f := [sim.fighting(0), sim.fighting(1)]
		if coop != null and coop.ls == null:
			return "Waiting for the battle to start."
		return "Tap a ship of yours to command it. %s: %d fighting; the enemy: %d." % [side_names[player_side], f[player_side], f[1 - player_side]]
	if mine.size() > 1:
		return "%d ships selected. Tap the sea to sail, an enemy to engage%s." % [mine.size(), " (Board armed: tap an enemy)" if arm == "board" else ""]
	var s := mine[0]
	var mode: String = ["holding her course", "sailing to the mark", "engaging", "closing to board", "running for it", "holding a heading",
		"sent in: lit within %d m" % SeaSim.FS_LIGHT_M][sim.s_mode[s]]
	if ST.is_fire(sim.s_type[s]) and sim.s_lit[s] >= 0:
		mode = "ablaze, her helm lashed" if sim.s_aband[s] != 0 else "ablaze, steering for her mark"
	if sim.s_grap[s] >= 0:
		mode = "grappled: boarding" if sim.s_boarder[s] != 0 else "grappled: repelling boarders"
	if sim.s_douse[s] != 0:
		mode += ", all hands dousing the fire (guns silent)"
	elif sim.s_burn[s] > 0 and not ST.is_fire(sim.s_type[s]):
		mode += ", on fire"
	var sails: String = ["hove to", "battle sail", "full sail"][sim.s_sail[s]]
	# The first time a setting shows, its speed share too ("battle sail (75 %)").
	if not _pct_shown.has(sim.s_sail[s]):
		_pct_shown[sim.s_sail[s]] = _clock
	if _clock - float(_pct_shown[sim.s_sail[s]]) < PCT_SEC:
		sails += " (%d %%)" % SeaSim.SAIL_PCT[sim.s_sail[s]]
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
	_close_help_card()
	for c in _bar.get_children():
		_bar.remove_child(c)  # (out of the tree now, so the new buttons keep their names)
		c.queue_free()
	var mine: Array[int] = []
	for s in selection:
		if sim.u_state[s] == SeaSim.S_SAIL and sim.u_side[s] == player_side and _mine(s):
			mine.append(s)
	if mine.is_empty() or not interactive:
		return
	var s0 := mine[0]
	var ty0 := sim.s_type[s0]
	# One order: its help (title, tip, hint), the handler (a long press gives the help card, not the order).
	var order_cb := func(h: Dictionary, cb: Callable) -> Callable:
		return func():
			if _lp_swallow:
				_lp_swallow = false  # (the release of a long press: it opened the help card, not an order)
				return
			cb.call()
			if str(h["hint"]) != "":
				_show_hint(str(h["hint"]))
	var add := func(text: String, nm: String, on: bool, cb: Callable) -> void:
		var h := SeaBook.order_help(nm, ty0, sim.s_fire[s0] != 0)
		var b := Kit.button(text, order_cb.call(h, cb), 62, 12)
		b.name = nm
		Kit.tip(b, str(h["title"]), str(h["tip"]))
		_arm_long_help(b, h)
		b.custom_minimum_size.y = 32
		BTheme.plate(b, false, on, false)   # (Kit.button has the motion already; lit when the order is on)
		_bar.add_child(b)
	# The sail settings and the shot kinds are choices of one: a capsule each, the one in force lit, the labels as before.
	var group := func(items: Array) -> void:   # [[text, name, on, cb], ...]
		var opts: Array = []
		var lit = null
		var by := {}
		for it in items:
			opts.append([it[0], it[1]])
			if it[2]:
				lit = it[1]
			by[it[1]] = [SeaBook.order_help(str(it[1]), ty0, sim.s_fire[s0] != 0), it[3]]
		var sg := BTheme.capsule(opts, func(nm: String): order_cb.call(by[nm][0], by[nm][1]).call(), "", 12, 62.0, 32.0, lit)
		for gb in sg.buttons():
			var gn: String = str(gb.get_meta("seg_value"))
			gb.name = gn
			var gh: Dictionary = by[gn][0]
			Kit.tip(gb, str(gh["title"]), str(gh["tip"]))
			_arm_long_help(gb, gh)
		_bar.add_child(sg)
	group.call([["Full sail", "sea_full", sim.s_sail[s0] == 2, func(): _orders_all(SeaSim.O_SAILS, {"on": 2})],
		["Battle sail", "sea_battle_sail", sim.s_sail[s0] == 1, func(): _orders_all(SeaSim.O_SAILS, {"on": 1})],
		["Heave to", "sea_stop", sim.s_sail[s0] == 0, func(): _orders_all(SeaSim.O_SAILS, {"on": 0})]])
	group.call([["Round", "sea_round", sim.s_shot[s0] == ST.SHOT_ROUND, func(): _orders_all(SeaSim.O_SHOT, {"on": ST.SHOT_ROUND})],
		["Chain", "sea_chain", sim.s_shot[s0] == ST.SHOT_CHAIN, func(): _orders_all(SeaSim.O_SHOT, {"on": ST.SHOT_CHAIN})],
		["Grape", "sea_grape", sim.s_shot[s0] == ST.SHOT_GRAPE, func(): _orders_all(SeaSim.O_SHOT, {"on": ST.SHOT_GRAPE})]])
	add.call("Fire at will" if sim.s_fire[s0] != 0 else "Hold fire", "sea_fire", sim.s_fire[s0] != 0,
		func(): _orders_all(SeaSim.O_FIRE, {"on": 0 if sim.s_fire[s0] != 0 else 1}))
	add.call("Board", "sea_board", arm == "board", func():
		arm = "" if arm == "board" else "board"
		_refresh_bar())
	add.call("Hold course", "sea_hold", sim.s_mode[s0] == SeaSim.M_FREE, func(): _orders_all(SeaSim.O_HOLD, {}))
	add.call("Flee", "sea_flee", sim.s_mode[s0] == SeaSim.M_FLEE, func(): _orders_all(SeaSim.O_FLEE, {}))
	# Douse: only while a selected ship burns; toggled (on for the burning ones, off for all).
	var burning := false
	var dousing := false
	for s in mine:
		if sim.s_burn[s] > 0 and not ST.is_fire(sim.s_type[s]):
			burning = true
			dousing = dousing or sim.s_douse[s] != 0
	if burning:
		add.call("Douse", "sea_douse", dousing, func():
			if not dousing:
				_count("douse")
			_orders_all(SeaSim.O_DOUSE, {"on": 0 if dousing else 1}))
	var fires := false
	for s in mine:
		if ST.is_fire(sim.s_type[s]) and sim.s_lit[s] < 0:
			fires = true
	if fires:
		# (N3c) A fire ship: tap an enemy to send her in (lit close, when she
		# can lie the course), or light her now.
		add.call("Light her", "sea_light", false, func(): _orders_all(SeaSim.O_LIGHT, {}))
	var tos := _gift_targets()
	if not tos.is_empty():
		add.call("Gift to " + coop.player_name(int(tos[0])) if tos.size() == 1 else "Gift to...", "sea_gift", false, _gift)


## (Douse) Bits of the selection the bar depends on: burning (1), dousing (2) per ship.
func _bar_fire_key() -> int:
	var k := 0
	for s in selection:
		if s < 0 or s >= sim.n_units:
			continue
		k = k * 4 + (1 if sim.s_burn[s] > 0 and sim.u_state[s] == SeaSim.S_SAIL else 0) + (2 if sim.s_douse[s] != 0 else 0)
		k &= 0x3FFFFFFF
	return k


## A telemetry counter of this battle's inputs (view only): kept in
## input_counts and sent as a "sea_input" record.
func _count(key: String) -> void:
	input_counts[key] = int(input_counts.get(key, 0)) + 1
	var tele := get_node_or_null("/root/Telemetry")
	if tele != null:
		tele.event("sea_input", {"key": key, "n": int(input_counts[key]), "tick": sim.tick})


## The 3 s hint line under the row.
func _show_hint(text: String) -> void:
	_hint_lbl.text = text
	_hint_lbl.visible = true
	_hint_t = _clock


## A long press (LONG_HELP s) on an order button opens its help card instead
## of giving the order; hovering shows its tooltip on a desktop.
func _arm_long_help(b: Button, h: Dictionary) -> void:
	b.set_meta("tip_host_skip", true)  # (the kit's touch long-press tip box stays out: this opens the help card)
	b.button_down.connect(func():
		_lp_swallow = false
		_lp_token += 1
		var tok := _lp_token
		var ref: WeakRef = weakref(b)
		get_tree().create_timer(LONG_HELP).timeout.connect(func():
			var bb := ref.get_ref() as Button
			if tok == _lp_token and bb != null and bb.is_pressed():
				_lp_swallow = true
				_open_help_card(h)))
	b.button_up.connect(func(): _lp_token += 1)


func _open_help_card(h: Dictionary) -> void:
	_close_help_card()
	var root: Control = _hud.get_child(0)
	_help_catch = Control.new()
	_help_catch.name = "sea_help_catch"
	_help_catch.set_anchors_preset(Control.PRESET_FULL_RECT)
	_help_catch.mouse_filter = Control.MOUSE_FILTER_STOP
	_help_catch.gui_input.connect(func(e: InputEvent):
		if (e is InputEventMouseButton and e.pressed) or (e is InputEventScreenTouch and e.pressed):
			_close_help_card())
	root.add_child(_help_catch)
	var p := Kit.trim_panel(Color(Kit.PANEL_BG, 0.97), 14)   # the kit's tip plate, with the whole help as its body
	p.name = "sea_help_card"
	p.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	p.grow_horizontal = Control.GROW_DIRECTION_BOTH
	p.grow_vertical = Control.GROW_DIRECTION_BEGIN
	p.offset_bottom = -(_bar.get_global_rect().size.y + _info.get_global_rect().size.y + 14)
	var v := Kit.vbox(6)
	p.add_child(v)
	var ht := Kit.title(str(h["title"]), 18)
	ht.name = "sea_help_title"
	v.add_child(ht)
	v.add_child(Kit.rule())
	v.add_child(Kit.label(str(h["tip"]), Kit.FONT, Kit.COL_BONE, true))
	if str(h["more"]) != "":
		v.add_child(Kit.label(str(h["more"]), Kit.FONT_SMALL, Color(0.82, 0.88, 0.92), true))
	v.add_child(Kit.label("Tap anywhere to close.", Kit.FONT_SMALL, Kit.COL_DIM))
	p.custom_minimum_size = Vector2(minf(440.0, get_viewport_rect().size.x - 24.0), 0)
	root.add_child(p)
	_help_card = p
	AudioFx.click()


func _close_help_card() -> void:
	if _help_card != null:
		_help_card.queue_free()
		_help_card = null
	if _help_catch != null:
		_help_catch.queue_free()
		_help_catch = null


func _open_book() -> void:
	if book.visible:
		return
	var s := 0
	for x in selection:
		s = x
		break
	if selection.is_empty():
		for u in sim.n_units:
			if sim.u_side[u] == player_side:
				s = u
				break
	_close_help_card()
	if coop == null and speed_q != 0:
		_book_resume = speed_q  # (solo: the battle waits while the book is open)
		speed_q = 0
	book.open(sim, s)


func _book_closed() -> void:
	if _book_resume > 0 and speed_q == 0:
		speed_q = _book_resume
	_book_resume = -1


func _orders_all(typ: int, extra: Dictionary) -> void:
	for s in selection:
		if sim.u_side[s] != player_side or sim.u_state[s] != SeaSim.S_SAIL or not _mine(s):
			continue
		var o := {"tick": sim.tick, "type": typ, "unit": s}
		o.merge(extra)
		order(o)
	AudioFx.click()
	# The bar shows the new setting once the order is applied (next tick).
	get_tree().create_timer(0.15).timeout.connect(_refresh_bar)


## Issue a sim order (solo: straight into the sim at its current tick; live
## co-op: through the lockstep, for this player's own ships only).
func order(o: Dictionary) -> void:
	if not interactive or sim.decided_tick >= 0:
		return
	if coop != null:
		if not coop.can_issue():
			return
		var u := int(o.get("unit", -1))
		if u >= 0 and not coop.can_order(u):
			_not_mine_hint(u)
			return
		coop.issue(o)
		return
	sim.queue_order(o)


func _set_speed(q: int) -> void:
	speed_q = q
	AudioFx.click()


## A speed button: solo it applies; live co-op II asks to pause / resume and
## a speed is a vote (Lockstep), applied at its frame when agreed.
func _on_speed(q: int) -> void:
	if coop == null:
		_set_speed(q)
		return
	AudioFx.click()
	var ls = coop.ls
	if ls == null:
		return
	if q == 0:
		coop.request_pause()
		return
	if ls.paused != 0:
		coop.request_pause()  # (a speed while paused: resume first)
	var mine: bool = ls.vote_speed_by == coop.me
	if mine and q == ls.vote_speed_q:
		return
	if q == ls.speed_q:
		if mine:
			coop.request_speed(ls.vote_speed_q)  # (choosing the speed in force withdraws the proposal)
		return
	coop.request_speed(q)


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
	_rose.draw_line(tail, tip, SeaKey.col("wind"), 3.0, true)
	var side := Vector2(-wt.y, wt.x)
	_rose.draw_colored_polygon(PackedVector2Array([tip + wt * 3, tip - wt * 8 + side * 6, tip - wt * 8 - side * 6]), SeaKey.col("wind"))
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
	var p := Kit.trim_panel(Color(Kit.PANEL_BG, 0.97), 18)
	p.name = "sea_end_panel"
	p.set_anchors_preset(Control.PRESET_CENTER)
	p.grow_horizontal = Control.GROW_DIRECTION_BOTH
	p.grow_vertical = Control.GROW_DIRECTION_BOTH
	var v := Kit.vbox(8)
	p.add_child(v)
	var et := Kit.title("VICTORY" if won else "DEFEAT", 28, Kit.COL_GOOD if won else Kit.COL_BAD)
	et.name = "sea_end_title"
	et.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(et)
	v.add_child(Kit.rule())
	var r := sim.result()
	for sd in [player_side, 1 - player_side]:
		var t: Dictionary = r["sides"][sd]
		v.add_child(Kit.label("%s: %d ships, %d still fighting, %d sunk, %d taken, %d escaped; crews %d of %d." % [
			side_names[sd], int(t["ships"]), int(t["fighting"]), int(t["sunk"]), int(t["taken"]), int(t["fled"]),
			int(t["crew"]), int(t["crew0"])], Kit.FONT_SMALL, Color.WHITE, true))
	var b := Kit.button("Continue", func(): exit_requested.emit(), 140)
	b.name = "sea_continue"
	v.add_child(b)
	_cont_btn = b
	if coop != null and coop.ls != null and coop.final_frame < 0:
		b.disabled = true  # (live co-op: the result is complete at the final frame)
		b.text = "Finishing..."
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
	var p := Kit.trim_panel(Color(Kit.PANEL_BG, 0.97), 18)
	p.name = "sea_leave_panel"
	p.set_anchors_preset(Control.PRESET_CENTER)
	p.grow_horizontal = Control.GROW_DIRECTION_BOTH
	p.grow_vertical = Control.GROW_DIRECTION_BOTH
	var v := Kit.vbox(8)
	p.add_child(v)
	var lt := Kit.title("Leave the battle?", 22)
	lt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(lt)
	v.add_child(Kit.rule())
	var txt := "It counts as lost: your ships still fighting make their escape, the struck are taken."
	if coop != null and _coop_others_in():
		txt = "Your ships go to %s." % _coop_heir_name()
	v.add_child(Kit.label(txt, Kit.FONT, Kit.COL_BONE, true))
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
				_on_speed(0 if speed_q != 0 or coop != null else 4)
			KEY_1:
				_on_speed(4)
			KEY_2:
				_on_speed(8)
			KEY_3:
				_on_speed(16)
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
		if not _mine(s):
			_not_mine_hint(s)
			return
		if double:
			selection.clear()
			for k in sim.n_units:
				if sim.u_side[k] == player_side and sim.u_state[k] == SeaSim.S_SAIL and _mine(k):
					selection.append(k)
		else:
			selection = [s]
		arm = ""
		AudioFx.click()
		_refresh_bar()
		return
	var mine: Array[int] = []
	for k in selection:
		if sim.u_side[k] == player_side and sim.u_state[k] == SeaSim.S_SAIL and _mine(k):
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
		if sim.u_side[s] == player_side and sim.u_state[s] == SeaSim.S_SAIL and r.has_point(_pos(s)) and _mine(s):
			got.append(s)
	if not got.is_empty():
		selection = got
		arm = ""
		_refresh_bar()


# ------------------------------------------------------------------ co-op ---

func _mine(s: int) -> bool:
	return coop == null or coop.can_order(s)


func _not_mine_hint(s: int) -> void:
	if coop == null or coop_hud == null:
		return
	var c: int = coop.ls.commander(s) if coop.ls != null else -1
	coop_hud.flash("%s commands this ship." % (coop.player_name(c) if c >= 0 else "Nobody"), 2.0)


func _coop_ready() -> void:
	coop.auto_update = false
	_hud_shim = HudShim.new()
	_hud_shim.pause_button = _speed_btns[0]
	_hud_shim.speed_button = _speed_btns[1]
	var sp := Control.new()
	sp.visible = false
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(sp)
	_hud_shim.speed_panel = sp
	coop_hud = CoopHud.new()
	coop_hud.region_name = coop_region
	add_child(coop_hud)
	coop_hud.build(coop, _hud_shim)
	coop_hud.leave_pressed.connect(func(): exit_requested.emit())
	coop.changed.connect(_prune_selection)
	coop.resolved.connect(func():
		coop_hud.flash("The result is in on the server. Back to the campaign when you like.", 8.0))
	coop.note.connect(func(text: String, _kind: String): coop_hud.flash(text, 4.0))


## The session runs the lockstep frames due (wall time) and the sim steps
## with them; the view follows its sim (a snapshot restore swaps it).
func _coop_step(delta: float) -> void:
	if coop.ls != null and coop.ls.sim != sim:
		_rebind(coop.ls.sim)
	var n := sim.n_units
	var bx := PackedFloat32Array()
	var by := PackedFloat32Array()
	var bh := PackedFloat32Array()
	bx.resize(n)
	by.resize(n)
	bh.resize(n)
	for s in n:
		bx[s] = sim.s_x[s] / 1024.0
		by[s] = sim.s_y[s] / 1024.0
		bh[s] = sim.heading(s) * TAU / 1024.0
	var steps: int = coop.update(delta)
	_coop_test_aids()
	var ls = coop.ls
	if ls == null:
		_calpha = 1.0
		speed_q = 0
		return
	if ls.sim != sim:
		_rebind(ls.sim)
	elif steps > 0:
		_px = bx
		_py = by
		_ph = bh
	speed_q = 0 if ls.paused != 0 else int(ls.speed_q)
	var a := 1.0
	if ls.paused == 0:
		var fr: float = clampf(coop.wall_acc / TICK_SEC, 0.0, 1.0)
		a = fr if ls.speed_q >= 4 else clampf((ls.acc + fr * ls.speed_q) / 4.0, 0.0, 1.0)
	_calpha = a


## The session started or restored a snapshot: follow its sim.
func _rebind(s) -> void:
	sim = s
	_snap_prev()
	_ev_seen = sim.ev_n  # (a restored sim's past events are not replayed)
	_decided_at = -1.0 if sim.decided_tick < 0 else _clock
	_prune_selection()
	if selection.is_empty():
		for k in sim.n_units:
			if sim.u_side[k] == player_side and sim.u_state[k] == SeaSim.S_SAIL and _mine(k):
				selection.append(k)
				break
	_refresh_bar()


func _prune_selection() -> void:
	var keep: Array[int] = []
	for s in selection:
		if _mine(s) and sim.u_state[s] == SeaSim.S_SAIL:
			keep.append(s)
	if keep != selection:
		selection = keep
		_refresh_bar()


## Four times a second: the speed buttons follow the lockstep's pause and
## speed (and this player's open proposal); Continue at the end opens once
## the final frame is there.
func _coop_hud_tick() -> void:
	var ls = coop.ls
	if ls != null:
		var mine_q: int = ls.vote_speed_q if ls.vote_speed_by == coop.me else -1
		_light_speed(0 if ls.paused != 0 else SPEEDS.find(ls.speed_q))
		for i in _speed_btns.size():
			(_speed_btns[i] as Button).modulate = Color(0.7, 0.9, 1.0) if SPEEDS[i] != 0 and SPEEDS[i] == mine_q else Color.WHITE   # (this player's open vote)
	if _cont_btn != null and _cont_btn.disabled and (ls == null or coop.final_frame >= 0):
		_cont_btn.disabled = false
		_cont_btn.text = "Continue"


## The team-mates the selection can be given to: the other players taking
## part on this side, ascending.
func _gift_targets() -> Array:
	if coop == null or coop.ls == null:
		return []
	var out: Array = []
	for p in coop.teammates_in(coop.me):
		if coop.ls.side_of(int(p)) == player_side:
			out.append(int(p))
	return out


func _gift() -> void:
	var tos := _gift_targets()
	if tos.is_empty() or selection.is_empty():
		return
	if tos.size() == 1:
		_gift_to(int(tos[0]))
	elif coop_hud != null:
		coop_hud.pick_gift(tos, _gift_to)


func _gift_to(to: int) -> void:
	if selection.is_empty() or coop == null or coop.ls == null or not coop.ls.is_active(to):
		return
	coop.gift(selection, to)
	coop_hud.flash("%d ship%s given to %s." % [selection.size(), "" if selection.size() == 1 else "s", coop.player_name(to)], 2.5)
	selection.clear()
	_refresh_bar()


## Another player takes part and is connected (leaving hands them our ships).
func _coop_others_in() -> bool:
	if coop == null or coop.ls == null:
		return false
	for p in coop.ls.active_players():
		if p != coop.me and coop.connected(p):
			return true
	return false


## Who takes our ships when we leave: a connected player of our side, else
## the battle AI.
func _coop_heir_name() -> String:
	var side: int = coop.ls.side_of(coop.me)
	for p in coop.ls.side_players(side):
		if p != coop.me and coop.connected(p):
			return coop.player_name(p)
	return "the battle AI"


## Leaving a live sea battle: what to upload from this device ({res,
## decided}; {}: nothing - another player carries on or the host uploads).
## Leaves the room either way.
func coop_exit_result() -> Dictionary:
	if coop.ls == null:
		coop.leave()
		return {}
	var res: Dictionary = coop.final_result if not coop.final_result.is_empty() else sim.result()
	var out := {}
	if sim.winner >= 0:
		if coop.should_upload():
			coop.announce_upload()
			out = {"res": res, "decided": true}
	elif not _coop_others_in():
		# The last one here: a forfeit, as in a solo battle.
		out = {"res": res, "decided": false}
	coop.leave()
	return out


## Testing aids (as the land view's): --coop-start-alone (the host starts
## without waiting), --coop-select=mine (select own ships once it runs),
## --coop-auto-exit (back to the campaign once the battle is over).
func _coop_test_aids() -> void:
	for a in OS.get_cmdline_user_args():
		if a == "--coop-start-alone" and coop.phase == "lobby" and coop.is_host() and coop.room.is_open():
			coop.start_battle()
		elif a == "--coop-auto-exit" and coop.final_frame >= 0 and not has_meta("test_exit") and coop.ls != null \
				and coop.ls.frame >= coop.final_frame + 10:
			set_meta("test_exit", true)
			exit_requested.emit()


# ------------------------------------------------------------- deck inset ---
# (N3b) The deck melee of a grappled pair, drawn from the sim's figures
# (sim/sea_sim.gd "deck melee"): the boarder's deck on top, the rail, the
# defender's below, bows to the right.

## Which melee to show: one with a ship of the player's side (the latest),
## else the latest; the outcome stays 2.5 s after it ends.
func _inset_tick(delta: float) -> void:
	var best := -1
	var bt := -1
	for m in sim.n_units:
		if sim.k_on[m] == 0:
			continue
		var t := sim.s_grap[m]
		var ours := sim.u_side[m] == player_side or (t >= 0 and sim.u_side[t] == player_side)
		var key := sim.k_t0[m] + (1 << 20 if ours else 0)
		if key > bt:
			bt = key
			best = m
	if best != _inset_m and best >= 0:
		_inset_m = best
		_inset_t = sim.s_grap[best]
		_inset_end = ""
		_dk_pos.clear()
		_dk_smoke.clear()
	var showing := best >= 0 or (_inset_m >= 0 and _clock - _inset_end_t < 2.5 and _inset_end != "")
	if not showing:
		_inset_m = -1
	_inset.visible = showing and _inset_m >= 0
	if not _inset.visible:
		return
	var vp := get_viewport_rect().size
	var w := clampf(vp.x * 0.42, 220.0, 380.0)
	var h := w * 0.66
	_inset.size = Vector2(w, h)
	_inset.position = Vector2(vp.x - w - 6.0, 64.0)
	# Figures ease toward their cells; smoke drifts and fades.
	var base := _inset_m * SeaSim.FIG
	var k := clampf(delta * 9.0 * maxf(speed_q / 4.0, 0.25), 0.0, 1.0)
	for i in SeaSim.FIG:
		var fi := base + i
		if sim.f_n[fi] <= 0:
			_dk_pos.erase(i)
			continue
		var want := Vector2(sim.f_x[fi], sim.f_y[fi])
		_dk_pos[i] = want if not _dk_pos.has(i) else (_dk_pos[i] as Vector2).lerp(want, k)
	var keep: Array = []
	var dt := delta * maxf(speed_q / 4.0, 0.0)
	for sm in _dk_smoke:
		sm[1] = float(sm[1]) + dt
		if float(sm[1]) < 2.2:
			keep.append(sm)
	_dk_smoke = keep
	if sim.k_on[_inset_m] != 0 and speed_q > 0:
		_clash_t -= delta
		if _clash_t <= 0.0:
			_clash_t = 0.45
			AudioFx.play("melee", 0.55, 0.0, "melee")
	_inset.queue_redraw()


func _inset_input(e: InputEvent) -> void:
	var tapped := e is InputEventMouseButton and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT \
		and not (e as InputEventMouseButton).pressed
	if tapped and _inset_m >= 0 and _inset_m < sim.n_units:
		camera.position = _pos(_inset_m)
		_clamp_cam()


func _draw_inset() -> void:
	var m := _inset_m
	if m < 0:
		return
	var c := _inset
	var sz := c.size
	var t := _inset_t
	# The board: a dark wooden frame, the sea in it.
	c.draw_rect(Rect2(Vector2.ZERO, sz), Color(0.16, 0.11, 0.07, 0.94))
	c.draw_rect(Rect2(Vector2(3, 3), sz - Vector2(6, 6)), Color(0.12, 0.3, 0.4))
	var title := "Boarding"
	if t >= 0:
		title = "%s boards %s" % [_short(m), _short(t)]
	c.draw_string(ThemeDB.fallback_font, Vector2(8, 16), title, HORIZONTAL_ALIGNMENT_LEFT, sz.x - 16.0, 12, Color(1, 0.9, 0.6))
	var gw := sim.k_w[m]
	var hb := sim.k_hb[m]
	var gh := hb + sim.k_ht[m]
	if gw <= 0 or gh <= 0:
		return
	var top := 22.0
	var bottom := 30.0
	var cell := minf((sz.x - 16.0) / gw, (sz.y - top - bottom) / (gh + 0.6))
	var org := Vector2((sz.x - cell * gw) * 0.5, top + 2.0)
	var gap := cell * 0.6  # the water between the hulls
	var to_px := func(p: Vector2) -> Vector2:
		var y := p.y * cell + (gap if p.y >= hb else 0.0)
		return org + Vector2(p.x * cell + cell * 0.5, y + cell * 0.5)
	var cols := [_ship_col(m), _ship_col(t) if t >= 0 else _ship_col(m)]
	# The two hulls: planking, rail, masts.
	for side in 2:
		var x0 := sim.k_ax0[m] if side == 0 else sim.k_bx0[m]
		var ln := sim.k_la[m] if side == 0 else sim.k_lb[m]
		var y0 := 0 if side == 0 else hb
		var rows := hb if side == 0 else gh - hb
		var r := Rect2(org + Vector2(x0 * cell, y0 * cell + (gap if side == 1 else 0.0)), Vector2(ln * cell, rows * cell))
		var bow := r.position.x + r.size.x
		var hull := PackedVector2Array([r.position + Vector2(-cell * 0.2, -cell * 0.15), Vector2(bow - cell * 0.6, r.position.y - cell * 0.15),
			Vector2(bow + cell * 0.9, r.get_center().y), Vector2(bow - cell * 0.6, r.end.y + cell * 0.15),
			Vector2(r.position.x - cell * 0.2, r.end.y + cell * 0.15)])
		c.draw_colored_polygon(hull, COL_HULL)
		var dk := PackedVector2Array()
		var ctr := r.get_center()
		for v in hull:
			dk.append(ctr + (v - ctr) * Vector2(0.94, 0.8))
		c.draw_colored_polygon(dk, COL_DECK)
		# Planks along her length, the seams darker; a grating amidships.
		var nplank := int(rows * 2)
		for k2 in range(1, nplank):
			var py := r.position.y + r.size.y * k2 / nplank
			c.draw_line(Vector2(r.position.x, py), Vector2(bow - cell * 0.4, py), Color(0.45, 0.33, 0.2, 0.55), 1.0)
		c.draw_rect(Rect2(ctr - Vector2(cell * 0.7, cell * 0.35), Vector2(cell * 1.4, cell * 0.7)), Color(0.32, 0.22, 0.13, 0.8))
		var rail := hull.duplicate()
		rail.append(hull[0])
		c.draw_polyline(rail, (cols[side] as Color).darkened(0.25), maxf(cell * 0.14, 1.5), true)
		var ty := sim.s_type[m] if side == 0 else (sim.s_type[t] if t >= 0 else 0)
		for f in SeaSim._masts(ty):
			var mx := x0 + ln / 2 + int(f) * ln / 100
			var mp: Vector2 = to_px.call(Vector2(mx, y0 + rows / 2))
			c.draw_circle(mp + Vector2(1.5, 1.5), cell * 0.36, Color(0, 0, 0, 0.3))
			c.draw_circle(mp, cell * 0.33, Color(0.35, 0.24, 0.14))
	# Grapnel lines across the gap.
	var gy0 := org.y + hb * cell
	for k3 in 5:
		var gx := org.x + (gw * cell) * (0.15 + 0.17 * k3)
		c.draw_line(Vector2(gx, gy0 - cell * 0.2), Vector2(gx + cell * 0.3, gy0 + gap + cell * 0.2), Color(0.1, 0.07, 0.04), 1.2)
	# The men: shadows first, then each group as a little crowd.
	var base := m * SeaSim.FIG
	for i in _dk_pos:
		var p: Vector2 = to_px.call(_dk_pos[i])
		c.draw_circle(p + Vector2(cell * 0.12, cell * 0.16), cell * 0.4, Color(0, 0, 0, 0.25))
	for i in _dk_pos:
		var fi := base + int(i)
		var n := sim.f_n[fi]
		if n <= 0:
			continue
		var p2: Vector2 = to_px.call(_dk_pos[i])
		var col: Color = cols[sim.f_side[fi]]
		var kind := sim.f_kind[fi]
		var men := clampi(n, 1, 5)
		var r2 := cell * 0.17
		for j in men:
			var off := Vector2(cos(j * 2.4 + i), sin(j * 2.4 + i)) * (cell * 0.22 if men > 1 else 0.0)
			var body := col.darkened(0.15) if kind != 1 else col.darkened(0.35)
			c.draw_circle(p2 + off, r2, body)
			c.draw_circle(p2 + off + Vector2(0, -r2 * 0.4), r2 * 0.55, Color(0.86, 0.7, 0.55) if kind != 2 else Color(0.12, 0.1, 0.08))
		if kind == 2:
			c.draw_arc(p2, cell * 0.42, 0, TAU, 16, Color(1, 0.85, 0.3), 1.6, true)
		elif kind == 1:
			c.draw_line(p2 + Vector2(-r2, -r2), p2 + Vector2(r2, r2), Color(0.95, 0.95, 0.9, 0.8), 1.0)
		# Cold steel: sparks where it struck this moment.
		if sim.tick - sim.f_hit[fi] <= 1 and (int(i) + int(_clock * 8.0)) % 3 == 0:
			var fl := absf(sin(_clock * 23.0 + i))
			var sp := p2 + Vector2(cell * 0.2 * sin(i * 1.7), cell * 0.5 if sim.f_side[fi] == 0 else -cell * 0.5)
			for q in 4:
				var a := q * PI / 2.0 + PI / 4.0 + _clock * 9.0
				c.draw_line(sp, sp + Vector2(cos(a), sin(a)) * cell * (0.1 + 0.12 * fl), Color(1, 0.95, 0.7, 0.85), 1.0)
	# Powder smoke (pistols, muskets) drifting off.
	for sm in _dk_smoke:
		var age := float(sm[1])
		var sp2: Vector2 = to_px.call(sm[0]) + Vector2(age * cell * 0.7, -age * cell * 0.25)
		c.draw_circle(sp2, cell * (0.22 + age * 0.3) * float(sm[2]), Color(0.9, 0.9, 0.86, 0.38 * (1.0 - age / 2.2)))
	# Each side's men and heart.
	var men_n := [0, 0]
	for i2 in SeaSim.FIG:
		if sim.f_n[base + i2] > 0:
			men_n[sim.f_side[base + i2]] += sim.f_n[base + i2]
	var by := sz.y - bottom + 4.0
	for side in 2:
		var x := 8.0 + side * (sz.x * 0.5)
		var bw := sz.x * 0.5 - 16.0
		var mor := clampf(sim.k2_mor[m * 2 + side] / 100.0, 0.0, 1.0)
		c.draw_rect(Rect2(x, by, bw, 6), Color(0, 0, 0, 0.6))
		var bc: Color = cols[side]
		if bc.get_luminance() < 0.35:
			bc = bc.lightened(0.5)
		c.draw_rect(Rect2(x, by, bw * mor, 6), bc)
		var lbl := "%s %d men%s" % ["Boarders" if side == 0 else "Defenders", int(men_n[side]),
			"" if sim.k2_cap[m * 2 + side] != 0 else ", captain down"]
		c.draw_string(ThemeDB.fallback_font, Vector2(x, by + 19), lbl, HORIZONTAL_ALIGNMENT_LEFT, bw, 11, Color(0.95, 0.92, 0.85))
	if _inset_end != "" and sim.k_on[m] == 0:
		c.draw_rect(Rect2(Vector2(6, sz.y * 0.38), Vector2(sz.x - 12, 26)), Color(0, 0, 0, 0.7))
		c.draw_string(ThemeDB.fallback_font, Vector2(12, sz.y * 0.38 + 18), _inset_end, HORIZONTAL_ALIGNMENT_CENTER, sz.x - 24, 13,
			Color(1, 0.9, 0.6))


## A ship's short name for the inset title.
func _short(s: int) -> String:
	var d: Dictionary = (scenario.get("units", []) as Array)[s]
	if d.has("nm"):
		return str(d["nm"])
	return ("our " if sim.u_side[s] == player_side else "the enemy ") + ST.name_of(sim.s_type[s]).to_lower()
