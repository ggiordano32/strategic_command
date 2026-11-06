extends Node2D
## Battle view and input. Owns the sim, steps it at 10 Hz (scaled by the
## speed setting), uploads state to the renderer after each tick, and turns
## touch / mouse gestures into sim orders. It never writes sim state directly.

signal exit_requested

const AudioFx := preload("res://game/audio.gd")
const Tips := preload("res://game/campaign/tips.gd")
const TutorCard := preload("res://game/campaign/tutor_card.gd")
const BattleSim := preload("res://sim/battle_sim.gd")
const Scenarios := preload("res://sim/scenarios.gd")
const SoldierLayer := preload("res://game/soldier_layer.gd")
const TrayLayer := preload("res://game/tray_layer.gd")
const Overlay := preload("res://game/overlay.gd")
const Hud := preload("res://game/hud.gd")
const BTheme := preload("res://game/battle_theme.gd")
const BattleMenu := preload("res://game/battle_menu.gd")
const OrderPreview := preload("res://game/order_preview.gd")
const Quality := preload("res://game/quality.gd")
const TerrainLayer := preload("res://game/terrain_layer.gd")
const BattleLook := preload("res://game/battle_look.gd")
const BoardView := preload("res://game/board_view.gd")
const TableMotion := preload("res://game/table_motion.gd")
const ObliquePack := preload("res://game/oblique_pack.gd")
const KitOccluder := preload("res://game/kit_occluder.gd")
const BoardLayer := preload("res://game/board_layer.gd")
const BattleDof := preload("res://game/battle_dof.gd")
const TreeLayer := preload("res://game/tree_layer.gd")
const CityLayer := preload("res://game/city_layer.gd")
const WorksLayer := preload("res://game/works_layer.gd")
const ShipLayer := preload("res://game/ship_layer.gd")
const MapGen := preload("res://sim/mapgen.gd")
const Terrain := preload("res://sim/terrain.gd")
const UT := preload("res://sim/unit_types.gd")
const Controls := preload("res://game/controls.gd")
const UiScale := preload("res://game/ui_scale.gd")
const CoopHud := preload("res://game/coop_hud.gd")
const Lockstep := preload("res://sim/lockstep.gd")
const CData := preload("res://campaign/cdata.gd")
const FM := preload("res://sim/fixed_math.gd")
const OccView := preload("res://game/occupy_view.gd")
const Traits := preload("res://game/unit_traits.gd")
const View3D := preload("res://game/view3d.gd")

const PX_PER_M := 10.0
const M := 1024.0
const TICK_SEC := 0.1
const MAX_TICKS_PER_FRAME := 4
const SPEED_PRESETS := [2, 4, 8, 16]  # --speed=N (main.gd): N indexes these quarter-step speeds
const DRAG_THRESHOLD := 18.0      # screen px before a touch becomes a drag
const DOUBLE_TAP_SEC := 0.35
# Tap rules on the field (first match wins). "Selection" = units selected.
#   a tap within the loose marker radius (2.3x touch / 1.7x mouse) of one of
#     our units' markers -> select that unit (nearest marker wins), with or
#     without a selection; shift / ctrl / Add toggles it. Markers are hit
#     targets first, so a near miss never turns into a group move.
#   enemy unit under the tap, selection        -> attack (double tap: charge)
#   friendly unit's footprint (away from its marker), selection, plain tap
#     -> MOVE order to the tapped point (the "Move" flash: ordering into a
#     crowd); a double tap on it selects it; no selection: a tap selects
#   ground, selection                           -> move there
# A long press on any unit opens its book page. Drag with a selection (from
# anywhere, a crowd of our units included) draws the order line; rubber-band
# select needs an empty selection or shift/ctrl. Two-finger tap and the None
# button deselect.
# MOUSE (real mouse; the touch rules above are unchanged): left click selects
# (empty ground deselects), left drag is a selection box, right click orders
# (ground: the whole selection moves keeping its shape; enemy: attack; our
# unit: move to it; double = run / charge), right drag lays the selection out
# along the dragged line (the touch drag-to-line rule). Middle drag pans.
const SELECT_LONG_PRESS_SEC := 0.35  # a held mouse click (telemetry label only)
const UNDO_DEPTH := 5            # order batches Undo remembers
const UNDO_SHOW_SEC := 6.0       # the Undo button stays this long after each batch
const TIGHT_PICK_K := 1.0        # marker hit radius factor of the tight pick (counter tap_select_loose)
const END_BANNER_SEC := 1.5      # campaign battles: the end banner before returning
const DOUBLE_TAP_DIST := 48.0
# Two-finger tap = deselect all. Both fingers down within TWO_TAP_DOWN_MS of
# each other, both up within TWO_TAP_TOTAL_MS of the first touch, each moved
# under TWO_TAP_MOVE px (logical), no third finger. Any pinch / pan motion
# (a finger past TWO_TAP_MOVE) cancels it, so it cannot fire after those.
const TWO_TAP_DOWN_MS := 120
const TWO_TAP_TOTAL_MS := 250
const TWO_TAP_MOVE := 12.0
const MIN_LINE_M := 3.0           # shorter drags keep the current frontage
const ZOOM_MIN := 0.12
const ZOOM_MAX := 4.0
## The side this player fights on (0 bottom; head-to-head: 1 for the
## player on the top side).
var player_side := 0
const STATS_WINDOW := 20          # ticks (2 s) for sim ms average / worst
const TELEMETRY_SAMPLE_SEC := 5.0
# Ticks at which the state hash is reported, so runs of the same scenario and
# seed can be compared across devices (multiples of 10).
const HASH_CHECKPOINTS := [100, 300, 600, 1000, 1500, 2000, 3000, 4000]
const MAX_ORDER_EVENTS := 300

## Remembered for the page session (static: survives returning to the menu).
static var show_all_orders := false

var scenario_id := "skirmish"
var bounds_mode := false  # view-side: move orders go by bounds
var seed_value := 1
## Terrain kind for scenarios with generated terrain (Terrain.K_*), or -1
## for the scenario's own (random from the seed for the playable battles).
var terrain_kind := -1
## Ground palette for scenarios with generated terrain (MapGen.PAL_*; woods
## follow the palette, MapGen.PALETTE_FOREST), or -1 for the scenario's own.
var ground := -1
## A ready-made scenario (campaign battles) used instead of scenario_id.
var custom_scenario: Dictionary = {}
## Campaign faction index per unit (CBattle "unit_faction"): the soldiers'
## palettes (view only; empty: from each side's units, see SoldierLayer).
var unit_faction: Array = []
## Custom battle (view only): per sim side the faction key whose unit names the HUD shows ("" the
## rows' own); needs that faction's pack active (main.gd switches it for the battle).
var side_name_fkeys: Array = []
## Sandbox: battle AI skill for both sides (sim/ai_profile.gd), -1 = the
## scenario's own (campaign battles carry theirs in the scenario).
var ai_skill := -1
## Campaign battle: leaving before the battle is decided needs a second tap
## (the army withdraws and the battle counts as lost); the menu buttons
## read "Back to campaign".
var campaign_mode := false
## The guided first campaign's battle lesson (game/campaign/tutorial_battle.gd), or null: it sees every order queued
## and shows its cards and pointer on the HUD.
var tutorial = null
var _tip_card: TutorCard = null
var _prev_presenter := Callable()
## Campaign battles: Leave / Menu taps are ignored this long after the
## battle is shown (stray taps while it opens forfeited battles), then a
## tap asks in a modal (Stay / Leave). Seconds left (tests may zero it).
const LEAVE_GRACE_SEC := 3.0
var leave_grace := LEAVE_GRACE_SEC
var leave_dialog: Control  # the "Leave the battle?" modal (built on first use)
var _leave_text: Label
## End of the battle (docs/DESIGN.md "Battle end: End battle / Continue"):
## with end_choice on (campaign battles), an interactive battle decided for a
## side (not a draw) asks End battle / Continue in a modal over the field;
## Continue (sim ORDER_PURSUE) runs the pursuit on, the top-right button
## becoming "End battle" (sim ORDER_END), until the loser has left the field
## or the sim's hard stop. Custom battles and the sandbox keep their field
## result panel (end_choice off).
var end_choice := false
var end_dialog: Control  # the End battle / Continue modal (built on first use)
var _end_title: Label
var _end_text: Label
var _end_flow := false   # the choice was offered in this battle
var _end_sent := 0       # what this player chose: 1 Continue, 2 End battle
var _pursuit_view := false  # pursuing: the button reads End battle, the banner is small
var _end_banner := ""    # the decision banner's text (Victory / Defeat)
## Live co-op battle (game/net/coop_session.gd, milestone 5), or null: the
## session runs the lockstep layer and owns the sim once the battle starts
## (before that `sim` is a stand-in built from the same scenario for the
## lobby). Orders go through it, only for units this player commands;
## pause and speed are votes.
var coop = null
var coop_hud = null
var coop_region := ""
## Custom battle: CustomSetup.summary() of its setup (telemetry
## "custom_battle" at the end), else empty.
var custom_summary: Dictionary = {}

var sim: BattleSim
var camera: Camera2D
## The 3D battle view (BoardView.v3d; game/view3d.gd), else null. Its camera follows `camera` every frame; the turn and the tilt
## are BoardView's yaw and elevation (set by `_v3d_turn`), the gestures in _update_pinch, _right_motion and _keys_held.
var view3d: Node3D = null
var _v3d_yaw_vel := 0.0       # radians a second still turning after a twist or a drag (inertia)
var _v3d_turning := false     # a twist or a turning drag is under way (no inertia meanwhile)
var _v3d_acc_ang := 0.0       # the twist so far in this two-finger gesture (until its dead zone)
var _v3d_twist := false       # the twist passed its dead zone in this gesture
var _v3d_c3 := Vector2(-1e9, -1e9)   # three fingers: their centroid at the last step
var _pinch_ang := 0.0
var _v3d_twist_prev := 1e9    # the two fingers' angle at the last frame (1e9: none yet)
var _rmb_turn := false        # 3D: the right drag turns and tilts the camera
var terrain: TerrainLayer
var city: CityLayer
var works: WorksLayer
var ships: ShipLayer   # (2026-11-05) the ships lying off the shore (under the men)
## Deployment: the field works palette's armed mode ("" none, "stakes",
## "caltrops", "rotate", "remove") and a stakes line being dragged.
var works_mode := ""
var _works_drag := false
var trees: TreeLayer
var soldiers: SoldierLayer
var trays   # TrayLayer: the movement trays under the men
var overlay: Overlay
var hud: Hud
var orders: OrderPreview  # queued-but-unapplied orders, for immediate display

var paused := false
## Speed in quarter steps (4 = 1x; Lockstep.SPEED_Q_MIN..MAX). Solo it is
## the battle's speed; in co-op a copy of Lockstep.speed_q (telemetry).
var speed_q := 4
var _shown_speed := Vector2i(-1, -1)  # (speed, slider) last shown on the HUD
var interactive := true
## Tabletop pass 5, the dive (game/table_motion.gd): set by the screens that open a battle for a player; the camera starts high
## above the table and drops to the fit in DIVE_SEC (a tap or key skips). `dive_t` is the seconds into it, -1 when not diving.
var dive := false
var dive_t := -1.0
const DIVE_SEC := 1.2
const DIVE_HUD_SEC := 0.4      # the HUD fades in over the last part
const DIVE_START := 0.35       # the first zoom, as a share of the fit
var _dive_z0 := 0.4
var _dive_z1 := 1.0
var _dive_p0 := Vector2.ZERO
var _dive_p1 := Vector2.ZERO
var _dive_mod: CanvasModulate
var _dive_hold := -1.0
var bench_mode := false
## Primary selected unit (last one picked), -1 if none.
var selected := -1
## Every selected unit; `selected` is one of them.
var selection: Array[int] = []
## Control groups (docs/design/ui.md "Control groups"): n (1..9) -> unit ids of this player's side. View state of this
## peer only: never in the sim, a lockstep input or a hash; it resets with the battle.
const GROUP_DOUBLE_MS := 400   # the same group again within this centres the camera on it
var control_groups := {}
var _cg_last_n := 0
var _cg_last_ms := -100000
## "+ Add" mode: taps on units and cards add to / remove from the selection.
var add_mode := false
## "Release" pressed: the next tap on an enemy unit lets the selected
## handlers' war dogs loose at it (any other tap cancels).
var release_armed := false
## A character's act armed (docs/DESIGN.md "Heroes and agents"):
## BattleSim.ORDER_SABOTAGE / ORDER_ATTEMPT / ORDER_PARLEY, 0 none; the next
## tap on its target (an enemy battery or a shut gate; an enemy hero or
## general; a routing or wavering enemy unit) gives it, any other cancels.
var char_armed := 0

var _acc := 0.0
var _sim_ms := PackedFloat64Array()
var _upload_ms := 0.0
var _hash_text := "--------"
var _card_timer := 0.0

# Benchmark bookkeeping.
var _bench_frames := PackedFloat64Array()
var _bench_ticks := PackedFloat64Array()
var _bench_done := false
var _decided_tick := -1
var _result_shown := false
var _paused_before_book := false

# Telemetry (view only; never touches sim state).
var _tele: Node = null
var _win_frames := PackedFloat64Array()
var _win_sim := PackedFloat64Array()
var _win_time := 0.0
var _input_counts := {}
var _orders_by_type := {}
var _player_orders := 0
var _order_events := 0
var _checkpoint_hashes := {}
var _start_msec := 0
var _ended := false

# Gesture state.
var _touches: Dictionary = {}      # index -> current screen pos
var _primary := -1                 # touch index of the single-finger gesture
var _press_pos := Vector2.ZERO
var _dragging := false
var _gesture_multi := false        # two-finger gesture in progress
var _pinch_dist := 0.0
var _tt_t0 := 0                    # msec of the first finger down (two-finger tap)
var _tt_ok := false                # still a possible two-finger tap
var _tt_start: Dictionary = {}     # index -> press pos
var _pinch_mid := Vector2.ZERO
var _last_tap_time := -10.0
var _last_tap_pos := Vector2.ZERO
var _mouse_pan := false
# Right button (real mouse only, the Rome scheme): click = order, drag = line.
var _rmb := false
var _rmb_pos := Vector2.ZERO
var _rmb_drag := false      # the drag lays out a line (preview shown)
var _rmb_pan := false       # nothing selected: the drag pans
var _rmb_order := false     # inside _tap for a right click: never selects
var _rmb_shift := false     # Shift held at the right press: the order adds a waypoint
var _last_rtap_time := -10.0
var _last_rtap_pos := Vector2.ZERO
# Modifiers of the last left mouse press (Shift / Ctrl / Cmd add to the
# selection; Alt starts a group move) - read from the event itself, which
# is reliable in browsers where key state can be missed.
var _mouse_add := false
var _mouse_alt := false
# Box select (mouse drag on empty ground with nothing selected).
var _box := false
# Group move: three fingers or Alt / G + drag. Units, their start anchors
# and facings, the group centre (sim units), and the gesture's translation
# (world px) and rotation (radians).
var _gm := false            # ghost shown, orders on release
var _gm_pending := false    # three fingers down, not yet past the threshold
var _gm_mouse := false
var _gm_units: Array[int] = []
var _gm_base: Array = []
var _gm_centre := Vector2.ZERO
var _gm_move := Vector2.ZERO
var _gm_rot := 0.0
var _gm_start_mid := Vector2.ZERO
var _gm_start_ang: Array = []
var _gm_start_keys: Array = []
var _gm_mouse_start := Vector2.ZERO
# Long press on a unit on the field opens its unit book page.
var _field_lp_start := -1.0
var _press_sec := 0.0          # when the primary touch went down (s)
var _exit_timer := -1.0        # campaign battle decided: seconds until we return
var _paused_before_controls := false
var menu: Control = null   # the Menu overlay (built on first use)
var _paused_before_menu := false
const GM_MOVE_PX := 24.0      # three-finger movement before the ghost appears
const GM_TURN_RAD := 0.14     # ... or this much twist (8 degrees)
const GM_STEP := PI / 12.0    # wheel / Q / E turn step (15 degrees)
const PAN_SPEED := 900.0      # screen px per second for keyboard panning


func _ready() -> void:
	# The web's oblique sheets are a separate pack (game/oblique_pack.gd): start the fetch if the menu has not (or ask
	# once more after a cancel), and hold the battle's start while it runs so the first oblique battle already draws the
	# real sheets. Cancelled or failed: this battle is drawn from the top (BoardView.web_top).
	var obp := ObliquePack.ensure(false, true)
	if obp != null:
		await obp.wait()
	BoardView.web_top = OS.has_feature("web") and not ObliquePack.sheets_present()
	sim = BattleSim.new()
	var scn := custom_scenario if not custom_scenario.is_empty() else Scenarios.make(scenario_id)
	if unit_faction.is_empty() and scn.get("unit_faction") is Array:
		unit_faction = scn["unit_faction"]  # (the West scenarios' factions: Scenarios.west_factions; view only)
	if terrain_kind >= 0 and scn.has("terrain"):
		scn["terrain"]["kind"] = terrain_kind
	var gr := ground
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--force-terrain="):
			# Testing aid: generated terrain of this kind on any scenario.
			scn["terrain"] = {"kind": int(a.get_slice("=", 1))}
		elif a.begins_with("--ground="):
			gr = int(a.get_slice("=", 1))  # testing aid: ground palette (and its woods)
	if gr >= 0 and scn.has("terrain") and not (scn["terrain"] as Dictionary).has("city"):
		scn["terrain"]["ground"] = gr
		scn["terrain"]["forest"] = MapGen.PALETTE_FOREST[clampi(gr, 0, MapGen.PALETTE_FOREST.size() - 1)]
	if ai_skill >= 0 and not campaign_mode:
		scn["ai_skill"] = [ai_skill, ai_skill]
	sim.setup(scn, seed_value)
	bench_mode = sim.is_ai_side(0) and sim.is_ai_side(1)
	interactive = not sim.is_ai_side(player_side)
	# The board transform (tabletop pass 3): top view, or the oblique table (game/board_view.gd); every layer reads it.
	BoardView.begin(sim, PX_PER_M)

	# Ground: height shading, contours and the faint 50 m grid in one shader.
	var look_dio := BattleLook.is_diorama()
	var board: Node2D = null
	if look_dio and not ("--no-board" in OS.get_cmdline_user_args()):
		board = BoardLayer.new()
		add_child(board)
		board.setup(sim, PX_PER_M)
		BoardView.lift_node(board)
	terrain = TerrainLayer.new()
	add_child(terrain)
	terrain.setup(sim, PX_PER_M)

	# Settlement: buildings, walls, towers (static) and the gates.
	city = CityLayer.new()
	add_child(city)
	city.setup(sim, PX_PER_M)

	# Field works (stakes, caltrops, a camp's ditch and palisade): under the men.
	works = WorksLayer.new()
	works.viewer_side = player_side
	add_child(works)
	works.setup(sim, PX_PER_M)
	BoardView.lift_node(works)

	# Ships lying off the shore (a fleet supporting it): under the men, so their gun crews stand on the decks.
	ships = ShipLayer.new()
	add_child(ships)
	ships.setup(sim, PX_PER_M, scn.get("ships", []))
	BoardView.lift_node(ships)
	if sim.shp_on != 0 and not unit_faction.is_empty():
		# The ships' hulls and parties (units the sim adds): their fleet's faction (the scenario's "f"), else -1.
		var uf2: Array = unit_faction.duplicate()
		while uf2.size() < sim.n_units:
			uf2.append(-1)
		var shs: Array = scn.get("ships", [])
		for u in sim.n_units:
			if sim.u_ship[u] >= 0:
				var src: int = sim.sh_src[sim.u_ship[u]]
				if src >= 0 and src < shs.size() and int((shs[src] as Dictionary).get("f", -1)) >= 0:
					uf2[u] = int(shs[src]["f"])
		unit_faction = uf2

	# Movement trays under the men (tabletop pass 1).
	trays = TrayLayer.new()
	trays.player_side = player_side
	add_child(trays)
	trays.setup(sim, PX_PER_M)

	soldiers = SoldierLayer.new()
	soldiers.viewer_side = player_side
	soldiers.base_low = Quality.is_low()
	soldiers.unit_faction = unit_faction
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--factions=") and unit_faction.is_empty():
			# Testing aid: --factions=syracuse,carthage (side 0, side 1) sets the palettes.
			var fk: PackedStringArray = a.get_slice("=", 1).split(",")
			var uf: Array = []
			for u in sim.n_units:
				uf.append(CData.faction_index(fk[mini(sim.u_side[u] & 1, fk.size() - 1)]))
			soldiers.unit_faction = uf
	add_child(soldiers)
	soldiers.setup(sim, PX_PER_M)
	trays.soldiers = soldiers
	soldiers.probed.connect(_on_soldier_probe)

	# Trees above the soldiers; their canopies fade over men under them.
	trees = TreeLayer.new()
	trees.viewer_side = player_side
	add_child(trees)
	trees.setup(sim, PX_PER_M)
	if "--no-trees" in OS.get_cmdline_user_args():
		trees.visible = false  # testing aid: frame cost without the trees
	if BoardView.oblique and not BoardView.v3d and not ("--no-occluder" in OS.get_cmdline_user_args()):
		# The oblique view: the men behind a house, a wall or a rock are hidden by it (the kit's nearness).
		var occ := KitOccluder.new()
		add_child(occ)
		var land = terrain._land
		if occ.setup([city.kit, land.kit if land != null else null], sim.field_h / M * PX_PER_M):
			soldiers.set_occluder(occ.texture(), occ.near_r)
		else:
			occ.queue_free()
	print("map view: terrain %.1f ms, city %.1f ms, %d trees %.1f ms" % [terrain.build_ms, city.build_ms,
		trees.count, trees.build_ms])

	orders = OrderPreview.new()
	orders.sim = sim
	overlay = Overlay.new()
	overlay.sim = sim
	soldiers.shot_src = overlay
	overlay.orders = orders
	overlay.trays = trays
	overlay.soldiers = soldiers
	overlay.token_states = _card_states
	overlay.px_per_m = PX_PER_M
	add_child(overlay)
	BoardView.lift_node(overlay)

	camera = Camera2D.new()
	add_child(camera)
	camera.make_current()
	if BoardView.v3d:
		_v3d_build(board)

	if look_dio and not Quality.is_low() and DisplayServer.get_name() != "headless" and not BoardView.v3d \
			and not ("--no-dof" in OS.get_cmdline_user_args()):
		add_child(BattleDof.new())
	hud = Hud.new()
	add_child(hud)
	hud.unit_faction = soldiers.unit_faction
	if not side_name_fkeys.is_empty():
		var nf: Array = []
		for u in sim.n_units:
			var sk := int(sim.u_side[u]) & 1
			nf.append(CData.faction_index(str(side_name_fkeys[sk])) if sk < side_name_fkeys.size() and str(side_name_fkeys[sk]) != "" else -1)
		hud.unit_faction = nf
	hud.build(sim, player_side, interactive)
	hud.set_title(_hud_title(), hud.book.pack)
	var su: Array = scn.get("units", [])
	for k in mini(su.size(), sim.n_units):
		if str((su[k] as Dictionary).get("label", "")) != "":
			hud.unit_labels[k] = str(su[k]["label"])  # (reinforcements: their army's name)
	if campaign_mode:
		end_choice = true
		hud.result_menu_button.text = "Back to campaign"
		# The menu button is a bare 50 px icon; as "Leave" it needs its width
		# back and an exit icon instead of the menu glyph.
		hud.menu_button.text = "Leave"
		Hud.Kit.tip(hud.menu_button, "Leave", "Withdraw from the battle. It asks first.")
		hud.menu_button.custom_minimum_size.x = 0
		Hud.Kit.set_icon(hud.menu_button, "withdraw")
		# (set_icon centred the glyph while the button had no text: put it back
		# beside the word, or it draws over the "v".)
		hud.menu_button.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
	hud.set_stats_expanded(bench_mode)  # benchmarks show the full readout
	_fit_camera()
	_au_on = not bench_mode and AudioFx.on()
	if _au_on:
		# The bed: the sea in the map (a coast or port battle) is the coast bed, else the pack's inland one.
		var kind := "coast"
		if sim.sea_on == 0:
			kind = "inland_rome"
			for u in sim.n_units:
				if UT.pack_of(sim.u_otype[u]) == "west":
					kind = "inland_west"
					break
		AudioFx.set_battle_kind(kind)
		AudioFx.enter_battle()
	hud.card_pressed.connect(_on_card)
	hud.pause_pressed.connect(_toggle_pause)
	hud.speed_pressed.connect(func(): _count("speed_open"))
	hud.speed_chosen.connect(_on_speed_chosen)
	hud.menu_pressed.connect(_on_menu)
	hud.menu_button_pressed.connect(_on_menu_button)
	hud.run_pressed.connect(_toggle_run)
	hud.halt_pressed.connect(_halt)
	hud.fire_pressed.connect(_toggle_fire)
	hud.skirmish_pressed.connect(_toggle_skirmish)
	hud.stance_set.connect(_set_stance)
	hud.toggle_set.connect(_set_toggle)
	hud.bounds_pressed.connect(_toggle_bounds)
	hud.occupy_pressed.connect(_toggle_occupy)
	hud.waypoints_pressed.connect(_toggle_waypoints)
	hud.paths_toggled.connect(_on_paths_toggled)
	hud.deploy_pressed.connect(_toggle_deploy)
	hud.refill_pressed.connect(_toggle_refill)
	hud.ammo_pressed.connect(_toggle_ammo)
	hud.forage_pressed.connect(_toggle_forage)
	hud.drop_pressed.connect(_drop)
	hud.land_pressed.connect(_land)
	hud.kill_pressed.connect(_kill_beasts)
	hud.release_pressed.connect(_toggle_release)
	hud.char_pressed.connect(func(act: String): _toggle_char(int(CHAR_TYPES[act])))
	hud.withdraw_pressed.connect(_withdraw)
	hud.withdraw_all_pressed.connect(_withdraw_all)
	hud.group_pressed.connect(_select_group)
	hud.group_tapped.connect(_group_select)
	hud.group_new_pressed.connect(_group_new)
	hud.group_edit.connect(_group_assign)
	hud.ability_pressed.connect(_ability_pressed)
	hud.ability_set.connect(_ability_set)
	hud.card_states = _card_states
	hud.add_toggled.connect(func(on: bool):
		add_mode = on
		_count("add_mode_on" if on else "add_mode_off"))
	hud.orders_toggled.connect(_on_orders_toggled)
	hud.book_pressed.connect(func(): _open_book(-1, "book_open"))
	hud.card_long_pressed.connect(func(u: int): _open_book(sim.u_otype[u], "book_open_card"))
	hud.chip_book_pressed.connect(func(): _open_book(sim.u_otype[selected] if selected >= 0 and selected < sim.n_units else -1, "book_open_chip"))
	hud.cards_reordered.connect(func(): _count("card_reorder"))
	hud.book.closed.connect(_on_book_closed)
	hud.undo_pressed.connect(func():
		_count("undo_button")
		_undo())
	_place_connect()
	hud.deselect_pressed.connect(func():
		_count("deselect_button")
		_gm_cancel()
		_select(-1))
	hud.controls_pressed.connect(_open_controls)
	hud.ready_pressed.connect(_deploy_ready)
	if campaign_mode and coop == null:
		_prev_presenter = Tips.presenter
		Tips.presenter = _show_tip
	if tutorial != null:
		tutorial.attach(self)
	hud.works_pressed.connect(_on_works_mode)
	hud.controls.closed.connect(func(): _set_paused(_paused_before_controls))
	if coop != null:
		_coop_ready()
	hud.orders_button.set_pressed_no_signal(show_all_orders)
	if sim.city_on != 0 and sim.obs_on != 0:
		# Town maps: the Paths toggle (remembered; on by default).
		paths_on = CityLayer.load_paths_pref()
		hud.paths_button.visible = true
		hud.paths_button.set_pressed_no_signal(paths_on)
	hud.set_orders_text(show_all_orders)
	overlay.show_all_orders = show_all_orders
	overlay.player_side = player_side
	trays.player_side = player_side
	hud.update_cards(sim)
	_select(-1)
	_update_speed_text()
	_refresh_deploy()
	_apply_debug_args()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--frame-stats="):
			_fs_until = float(a.get_slice("=", 1)) + 3.0
	_dive_begin()
	_hash_text = "%08x" % sim.state_hash()
	_tele = get_node_or_null("/root/Telemetry")
	if _tele != null:
		_tele.page_hiding.connect(_on_page_hiding)
	_start_msec = Time.get_ticks_msec()
	_reset_window()
	_t("scenario_start", {"scenario": scenario_id, "seed": seed_value, "terrain": sim.ter_info,
		"terrain_build_ms": terrain.build_ms, "trees": trees.count, "trees_build_ms": trees.build_ms,
		"city_build_ms": city.build_ms, "soldiers": sim.n,
		"units": sim.n_units, "bench": bench_mode, "interactive": interactive,
		"speed": speed_q / 4.0, "start_tick": sim.tick, "hash_at_start": _hash_text})


## Testing aids (desktop only): -- --ai-both --skip-ticks=N --cam=x_m,y_m --zoom=Z
## --select=U[,U...] --pause fast-forward the sim and frame the camera for
## screenshots; --cam-unit=U centres on a unit after the skip; --attack=U:T
## gives unit U an attack order on unit T; --refill=U puts battery U into
## its refill mode (80 ticks run).
func _apply_debug_args() -> void:
	if "--ai-both" in OS.get_cmdline_user_args():
		sim.ai_sides[0] = 1  # screenshots: the AI fights for both sides
	for a in OS.get_cmdline_user_args():
		var v := a.get_slice("=", 1)
		if a.begins_with("--skip-ticks="):
			for t in int(v):
				sim.step()
			soldiers.upload()
			soldiers.set_alpha(1.0)
			_view_tick()
		elif a.begins_with("--cam="):
			_cam_to(Vector2(float(v.get_slice(",", 0)), float(v.get_slice(",", 1))) * PX_PER_M)
		elif a.begins_with("--cam-unit="):
			var cu := int(v)
			_cam_to(Vector2(sim.u_cx[cu], sim.u_cy[cu]) / M * PX_PER_M)
		elif a.begins_with("--zoom="):
			camera.zoom = Vector2.ONE * float(v)
		elif a == "--pause":
			_toggle_pause()
		elif a.begins_with("--select="):
			var first := true
			for part in v.split(","):
				if first:
					_select(int(part))
					first = false
				else:
					_toggle_in_selection(int(part))
		elif a.begins_with("--refill="):
			# --refill=U tells battery U to refill (it settles in over the
			# following ticks; combine with --skip-ticks to see it).
			sim.queue_order(BattleSim.make_refill_order(sim.tick, int(v), 1))
			for t in 80:
				sim.step()
			soldiers.upload()
		elif a.begins_with("--move-unit="):
			# --move-unit=U:x_m,y_m[,w_m]: unit U marched to (x, y) metres (front w, default 20 m) and the sim run until it
			# is there (at most 900 ticks); for screenshots of men inside walls (the oblique view's ghosts).
			var mu := int(v.get_slice(":", 0))
			var mxy := v.get_slice(":", 1).split(",")
			var mw := float(mxy[2]) if mxy.size() > 2 else 20.0
			var mai: int = sim.ai_sides[sim.u_side[mu]]
			sim.ai_sides[sim.u_side[mu]] = 0   # (its side's AI held while it marches, as --ai-both sets it)
			sim.queue_order(BattleSim.make_move_order(sim.tick, mu, int(float(mxy[0]) * M), int(float(mxy[1]) * M),
				sim.u_face[mu], int(mw * M), 0))
			for t in 900:
				sim.step()
				if t > 20 and sim.u_order[mu] == BattleSim.O_NONE:
					break
			sim.ai_sides[sim.u_side[mu]] = mai
			print("move-unit %d at %.0f,%.0f tick %d" % [mu, sim.u_cx[mu] / M, sim.u_cy[mu] / M, sim.tick])
			soldiers.upload()
			soldiers.set_alpha(1.0)
			_view_tick()
		elif a.begins_with("--attack="):
			# --attack=U:T orders unit U to attack (shoot) unit T.
			_queue(BattleSim.make_attack_order(0, int(v.get_slice(":", 0)), int(v.get_slice(":", 1)), 0))
		elif a.begins_with("--demo-place="):
			# --demo-place=dx_m,dy_m[,deg]: with --select, the placement tool's ghost (Confirm orders on) that far from the
			# primary unit, turned deg degrees if given, put up a few frames in (after the deployment); for screenshots and
			# --frame-stats.
			ConfirmOrders.force = "on"
			if sim.phase == BattleSim.PHASE_DEPLOY:
				sim.queue_order({"tick": sim.tick, "type": BattleSim.ORDER_READY, "who": 0})   # (the tool works in the battle phase)
				for t in 60:
					sim.step()
					if sim.phase != BattleSim.PHASE_DEPLOY:
						break
			_demo_place = v
		elif a.begins_with("--confirm-orders="):
			pass   # (read by ConfirmOrders.pref)
		elif a.begins_with("--demo-ghost="):
			# --demo-ghost=deg: the main line (no missiles) picked up as a
			# group, moved 60 m ahead and turned; for screenshots.
			_select(-1)
			for u in sim.n_units:
				if sim.u_side[u] == player_side and sim.u_cls[u] != UT.CLS_MISSILE and sim.u_cls[u] != UT.CLS_ART:
					if selection.is_empty():
						_select(u)
					else:
						_toggle_in_selection(u)
			_gm_begin()
			_gm_rot = deg_to_rad(float(v))
			_gm_move = Vector2(0, -60.0 * PX_PER_M)
			_gm_update()
		elif a.begins_with("--demo-wall="):
			# --demo-wall=down|up: the player's first wall unit selected, a
			# pending order down off its wall (down), or (up) brought down
			# first, then a tap on the wall's body; for screenshots (with
			# --pause the order stays pending, so its preview shows).
			var wu := -1
			for u in sim.n_units:
				if sim.u_side[u] == player_side and sim.u_wall[u] > 0:
					wu = u
					break
			if wu < 0:
				continue
			var sg: int = sim.u_wall[wu] - 1
			var inside: Vector2i = sim.wall_inside(sg, sim.u_cx[wu], sim.u_cy[wu])
			if v == "up":
				sim.queue_order(BattleSim.make_move_order(sim.tick, wu, inside.x, inside.y, sim.ws_dir[sg], 10 * 1024, 0))
				for t in 600:
					sim.step()
					if sim.u_wall[wu] == 0 and sim.u_stair[wu] == 0 and sim.u_order[wu] == BattleSim.O_NONE:
						break
				soldiers.upload()
				_view_tick()
			_select(wu)
			_cam_to(Vector2(sim.u_cx[wu], sim.u_cy[wu]) / M * PX_PER_M)
			if v == "up":
				# A tap on the wall's body (the parapet side), off the walkway.
				var mid := BattleSim.seg_pt(sim, sg, BattleSim.seg_len(sim, sg) / 2)
				var tx: int = mid.x + FM.cos_a(sim.ws_dir[sg]) * 3 * 1024 / 4096
				var ty: int = mid.y + FM.sin_a(sim.ws_dir[sg]) * 3 * 1024 / 4096
				_queue(BattleSim.make_move_order(0, wu, tx, ty, sim.u_face[wu], 10 * 1024, 0))
			else:
				_come_down()
		elif a == "--demo-breach":
			# --demo-breach: the stretch of the first wall unit knocked down and the three
			# buildings nearest it brought down (destruction); for screenshots.
			var wb := -1
			for u in sim.n_units:
				if sim.u_wall[u] > 0:
					wb = u
					break
			if wb >= 0:
				var sgb: int = sim.u_wall[wb] - 1
				var cb: int = sim.ws_cell.find(sgb + 1)
				while cb >= 0 and sim.ws_state[sgb] == 0:
					sim._destr_hit(((cb % sim.ob_w) << 11) + 1024, ((cb / sim.ob_w) << 11) + 1024, 500, -1, 100)
				var mp := BattleSim.seg_pt(sim, sgb, BattleSim.seg_len(sim, sgb) / 2)
				_cam_to(Vector2(mp) / M * PX_PER_M)
				var near: Array = []
				for b in sim.ob_hp.size():
					var cc: int = sim.ob_cell.find(b + 1)
					if cc >= 0:
						near.append([absi((cc % sim.ob_w) * 2048 - mp.x) + absi((cc / sim.ob_w) * 2048 - mp.y), cc])
				near.sort()
				for q in mini(3, near.size()):
					var c3: int = near[q][1]
					var b3: int = sim.ob_cell[c3] - 1
					while sim.ob_state[b3] == 0:
						sim._destr_hit(((c3 % sim.ob_w) << 11) + 1024, ((c3 / sim.ob_w) << 11) + 1024, 500, -1, 100)
				soldiers.upload()
				_view_tick()
		elif a == "--show-orders":
			hud.orders_button.button_pressed = true
		elif a == "--demo-orders":
			# Every other player unit advances 40 m in a wider line; the rest
			# stay put. For screenshots of the all-orders overlay.
			for u in sim.n_units:
				if sim.u_side[u] == player_side and u % 2 == 0:
					_queue(BattleSim.make_move_order(0, u, sim.u_ax[u] + 6 * 1024,
						sim.u_ay[u] - 40 * 1024, 760, 32 * 1024, 0))


## Paths overlay (town maps): the toggle, remembered; the hatch shows when a unit is selected, a route
## is being drawn, or the toggle is switched on, then fades over PATHS_FADE_SEC.
const PATHS_FADE_SEC := 2.0
var paths_on := false
var _paths_t := 99.0           # seconds since the hatch was last called for

func _on_paths_toggled(on: bool) -> void:
	paths_on = on
	CityLayer.save_paths_pref(on)
	_count("paths_toggle")
	if on:
		_paths_poke()
	else:
		_paths_apply()


func _paths_poke() -> void:
	_paths_t = 0.0
	_paths_apply()


func _paths_apply() -> void:
	if city == null:
		return
	var a := 0.0
	if paths_on and (not selection.is_empty() or _paths_t < 0.01):
		a = clampf(1.0 - _paths_t / PATHS_FADE_SEC, 0.0, 1.0)
	city.set_paths_alpha(a)


func _on_orders_toggled(on: bool) -> void:
	show_all_orders = on
	overlay.show_all_orders = on
	overlay.queue_redraw()
	_count("orders_overlay_on" if on else "orders_overlay_off")


## The top-right button: the Menu overlay in a battle of the battles list and the custom battles; in a campaign battle
## it is Leave (a confirm), and End battle once the battle is decided (as before).
func _on_menu_button() -> void:
	if campaign_mode or bench_mode or (_end_flow and sim.winner >= 0 and sim.ended == 0):
		_on_menu()
		return
	_open_menu()


## "Terrain" line for the top bar: the battle's name, then its ground.
func _hud_title() -> String:
	var t := ""
	match scenario_id:
		"campaign", "campaign_live":
			t = "Campaign battle"
		"custom":
			t = "Custom battle"
		_:
			t = Scenarios.title(scenario_id)
	var ter := terrain_name(sim).trim_prefix("Terrain: ")
	return "%s - %s" % [t, ter] if t != "" else ter.capitalize()


## The battle's Menu overlay (game/battle_menu.gd): Resume, Options, Controls, Leave the battle. Solo, the battle is
## paused while it is open and the pause is put back on close.
func _open_menu() -> void:
	_count("menu_open")
	if menu == null:
		menu = BattleMenu.new(self, _hud_title().get_slice(" - ", 0), hud.book.pack)
		menu.closed.connect(func(): _set_paused(_paused_before_menu))
		hud.add_child(menu)
		hud.add_ui_control(menu)
	if not menu.visible:
		_paused_before_menu = paused
		_set_paused(true)
	menu.open()
	_gm_cancel()
	overlay.preview_on = false
	_dragging = false
	_touches.clear()
	_primary = -1
	_gesture_multi = false


func _on_menu() -> void:
	if _end_flow and sim.winner >= 0 and sim.ended == 0:
		_count("end_battle_button")
		_end_battle()  # (decided, pursuing or still asked: the menu ends the battle)
		return
	if campaign_mode and sim.winner < 0:
		if leave_grace > 0.0:
			_count("leave_grace")  # (a stray tap while the battle opened)
			return
		if leave_dialog == null or not leave_dialog.visible:
			_show_leave_dialog()
		return
	_leave_now()


func _leave_now() -> void:
	if leave_dialog != null:
		leave_dialog.visible = false
	_end_scenario("menu")
	exit_requested.emit()


## The campaign battle's Leave confirm: a modal over the field (the dim
## catches every tap; the battle runs on).
func _show_leave_dialog() -> void:
	_count("leave_ask")
	if leave_dialog == null:
		var dim := ColorRect.new()
		dim.name = "leave_dialog"
		dim.color = Color(0, 0, 0, 0.45)
		dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		dim.mouse_filter = Control.MOUSE_FILTER_STOP
		var cc := CenterContainer.new()
		cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		dim.add_child(cc)
		var pn := Hud.Kit.trim_panel(Hud.Kit.PANEL_BG, 20.0)   # the dialog frame: trim, title face, rule
		pn.name = "leave_panel"
		cc.add_child(pn)
		var vb := Hud.Kit.vbox(14)
		pn.add_child(vb)
		var lt := Hud.Kit.title("Leave the battle?", 22)
		lt.name = "leave_title"
		lt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vb.add_child(lt)
		vb.add_child(Hud.Kit.rule())
		_leave_text = Hud.Kit.label("", Hud.Kit.FONT_TITLE, Hud.Kit.COL_BONE, true)
		_leave_text.custom_minimum_size = Vector2(minf(340.0, get_viewport_rect().size.x - 64.0), 0)
		vb.add_child(_leave_text)
		var row := Hud.Kit.hbox(12)
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		var stay := Hud.Kit.button("Stay", func():
			_count("leave_stay")
			leave_dialog.visible = false, 120)
		stay.name = "leave_stay"
		var go := Hud.Kit.icon_button("Leave", "withdraw", func():
			_count("leave_confirmed")
			_leave_now(), 120)
		go.name = "leave_go"
		go.add_theme_color_override("font_color", Hud.Kit.COL_BAD)
		BTheme.plate(stay)
		BTheme.plate(go)
		row.add_child(stay)
		row.add_child(go)
		vb.add_child(row)
		hud.add_child(dim)
		hud.add_ui_control(dim)
		leave_dialog = dim
	var txt := "Your army withdraws (a defeat)."
	if coop != null and _coop_others_in():
		txt = "Your units go to %s." % _coop_heir_name()
	_leave_text.text = txt
	leave_dialog.visible = true


## Campaign battle over: back to the campaign, which shows the full result.
## Same path as the old "Back to campaign" button.
func _leave_decided() -> void:
	_exit_timer = -1.0
	_on_menu()


## True once the battle has a winner (a campaign result can be applied).
func is_decided() -> bool:
	return sim.winner >= 0


# ------------------------------------------------------- end of battle ---

## The choice at the decision: offered with end_choice, to a player who
## commands (interactive), for a side's win (a draw ends at once).
func _end_choice_open() -> bool:
	return end_choice and interactive and not bench_mode and (sim.winner == 0 or sim.winner == 1) and sim.ended == 0


## The battle is decided: End battle / Continue in a modal over the field
## (the dim catches every tap; the pursuit runs on underneath). No answer:
## the sim ends it after END_AFTER as before.
func _show_end_dialog(title: String) -> void:
	_end_flow = true
	_end_banner = title
	if end_dialog == null:
		var dim := ColorRect.new()
		dim.name = "end_dialog"
		dim.color = Color(0, 0, 0, 0.45)
		dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		dim.mouse_filter = Control.MOUSE_FILTER_STOP
		var cc := CenterContainer.new()
		cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		dim.add_child(cc)
		var pn := Hud.Kit.trim_panel(Hud.Kit.PANEL_BG, 20.0)   # the dialog frame: trim, title face, rule
		pn.name = "end_panel"
		cc.add_child(pn)
		var vb := Hud.Kit.vbox(14)
		pn.add_child(vb)
		_end_title = Hud.Kit.title("", 28)
		_end_title.name = "end_title"
		_end_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vb.add_child(_end_title)
		vb.add_child(Hud.Kit.rule())
		_end_text = Hud.Kit.label("", Hud.Kit.FONT_TITLE, Hud.Kit.COL_BONE, true)
		_end_text.custom_minimum_size = Vector2(minf(340.0, get_viewport_rect().size.x - 64.0), 0)
		_end_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vb.add_child(_end_text)
		var row := Hud.Kit.hbox(12)
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		var go := Hud.Kit.icon_button("End battle", "withdraw", func():
			_count("end_choice_end")
			_end_battle(), 140)
		go.name = "end_go"
		var on := Hud.Kit.button("Continue", func():
			_count("end_choice_continue")
			_end_continue(), 140)
		on.name = "end_continue"
		BTheme.plate(go)
		BTheme.plate(on)
		row.add_child(go)
		row.add_child(on)
		vb.add_child(row)
		hud.add_child(dim)
		hud.add_ui_control(dim)
		end_dialog = dim
	_end_title.text = title
	_end_title.add_theme_color_override("font_color", Hud.Kit.COL_GOOD if sim.winner == player_side else Hud.Kit.COL_BAD)
	_end_text.text = "The enemy is broken and running." if sim.winner == player_side else "Your army is broken."
	var dl := destr_line(sim)
	if dl != "":
		_end_text.text += "\n" + dl
	end_dialog.visible = true
	_t("end_choice_shown", {"tick": sim.tick, "winner": sim.winner, "my_side": player_side})


## The sim input for the end of the battle (ORDER_PURSUE / ORDER_END), for
## this player's side: through the lockstep layer in co-op.
func _queue_end_input(typ: int) -> void:
	if coop != null:
		if coop.can_issue():
			coop.issue({"type": typ})
		return
	sim.queue_order({"tick": sim.tick, "type": typ, "side": player_side})


## Continue: the pursuit runs on (to the loser's last unit on the field or
## the sim's hard stop); End battle stays on the top-right button.
func _end_continue() -> void:
	if end_dialog != null:
		end_dialog.visible = false
	if sim.ended != 0 or _end_sent != 0:
		return
	_end_sent = 1
	_queue_end_input(BattleSim.ORDER_PURSUE)
	_t("end_choice", {"choice": "continue", "tick": sim.tick})
	_start_pursuit_view()


## End battle: the sim ends it on its next step; the view returns as at
## any end.
func _end_battle() -> void:
	if end_dialog != null:
		end_dialog.visible = false
	if sim.ended != 0 or _end_sent == 2:
		return
	_end_sent = 2
	_queue_end_input(BattleSim.ORDER_END)
	_t("end_choice", {"choice": "end", "tick": sim.tick, "pursuing": sim.pursue})
	if coop == null and paused:
		_set_paused(false)  # (solo: the end input needs a step)


func _start_pursuit_view() -> void:
	if _pursuit_view:
		return
	_pursuit_view = true
	hud.menu_button.text = "End battle"
	Hud.Kit.tip(hud.menu_button, "End battle", "End the battle now and go back to the campaign.")
	hud.banner.add_theme_font_size_override("font_size", 20)
	_refresh_pursuit_banner()


func _refresh_pursuit_banner() -> void:
	var left := maxi(sim.decided_tick + BattleSim.END_PURSUIT_MAX - sim.tick, 0) / 10
	hud.banner.text = "%s: pursuing\n%d:%02d left" % [_end_banner, left / 60, left % 60]
	hud.banner.visible = true


## Every frame while the choice is open or the pursuit runs: another
## player's Continue (the sim's pursue flag) closes the modal here too.
func _end_tick() -> void:
	if sim.ended != 0:
		if end_dialog != null:
			end_dialog.visible = false
		return
	if sim.pursue != 0 and not _pursuit_view:
		if end_dialog != null:
			end_dialog.visible = false
		_start_pursuit_view()
		if _end_sent != 1 and coop != null and coop_hud != null:
			coop_hud.flash("%s continues the pursuit" % _end_other_name(), 3.0)
	if _pursuit_view:
		_refresh_pursuit_banner()


## Another player of this battle (live co-op), for the pursuit flash.
func _end_other_name() -> String:
	if coop != null and coop.ls != null:
		for p in coop.ls.active_players():
			if p != coop.me:
				return coop.player_name(p)
	return "An ally"


## The battle ended after the choice was offered: the banner back at full
## size, telemetry of how it ended, and back to the campaign.
func _end_finished() -> void:
	if end_dialog != null:
		end_dialog.visible = false
	var how: String = sim.end_how()
	_count("end_pursuit_ended_" + how)
	_t("end_pursuit_ended", {"how": how, "pursue": sim.pursue, "tick": sim.tick,
		"secs": maxi(sim.tick - sim.decided_tick, 0) / 10, "mine": _end_sent})
	hud.banner.remove_theme_font_size_override("font_size")
	hud.banner.add_theme_font_size_override("font_size", Hud.BANNER_SIZE)
	hud.banner.text = _end_banner
	hud.banner.visible = true
	if campaign_mode:
		_exit_timer = 0.3 if _end_sent == 2 else END_BANNER_SEC


## Frame both armies in the part of the screen the HUD leaves clear (below
## the top buttons, above the group bar and unit cards).
func _fit_camera() -> void:
	var vp := get_viewport_rect().size
	var lo := Vector2(sim.field_w, sim.field_h)
	var hi := Vector2.ZERO
	for u in sim.n_units:
		lo = lo.min(Vector2(sim.u_minx[u], sim.u_miny[u]))
		hi = hi.max(Vector2(sim.u_maxx[u], sim.u_maxy[u]))
	lo = lo / M * PX_PER_M
	hi = hi / M * PX_PER_M
	if BoardView.oblique:
		# The armies' box on the board (the corners lifted by the ground under them).
		var bl := Vector2(1e9, 1e9)
		var bh := Vector2(-1e9, -1e9)
		for c in [lo, hi, Vector2(lo.x, hi.y), Vector2(hi.x, lo.y)]:
			var b := BoardView.to_board(c)
			bl = bl.min(b)
			bh = bh.max(b)
		lo = bl
		hi = bh
	var size := (hi - lo).max(Vector2(PX_PER_M * 40.0, PX_PER_M * 40.0))
	var top := hud.top_height()
	var bottom := hud.bottom_height()
	var clear := Rect2(0.0, top, vp.x, maxf(vp.y - top - bottom, vp.y * 0.3))
	var z := minf(clear.size.x / (size.x * 1.15), clear.size.y / (size.y * 1.25))
	z = clampf(z, ZOOM_MIN, ZOOM_MAX)
	camera.zoom = Vector2.ONE * z
	# camera.position is the board (world, in the top view) point at the viewport centre.
	camera.position = (lo + hi) * 0.5 + (vp * 0.5 - clear.get_center()) / z


## The dive onto the table (view only): from DIVE_START of the fit, centred on the field (the table's wood and the board's edge
## in view), to the fit with an ease-out; the HUD (a CanvasModulate on its layer) fades in over the last DIVE_HUD_SEC.
func _dive_begin() -> void:
	# (Testing aid --dive-hold=S: the dive held at S seconds, for the strip of shots; it ignores the other aids.)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--dive-hold="):
			_dive_hold = float(a.get_slice("=", 1))
	if _dive_hold < 0.0 and (not dive or bench_mode or not interactive or not TableMotion.allowed()):
		return
	_dive_z1 = camera.zoom.x
	_dive_p1 = camera.position
	_dive_z0 = _dive_z1 * DIVE_START
	var vp := get_viewport_rect().size
	var top := hud.top_height()
	var clear := Rect2(0.0, top, vp.x, maxf(vp.y - top - hud.bottom_height(), vp.y * 0.3))
	var fc := BoardView.to_board(Vector2(sim.field_w, sim.field_h) / M * PX_PER_M * 0.5)
	_dive_p0 = fc + (vp * 0.5 - clear.get_center()) / _dive_z0
	dive_t = 0.0
	_dive_mod = CanvasModulate.new()
	_dive_mod.color = Color(1, 1, 1, 0)
	hud.add_child(_dive_mod)
	_dive_apply()


func _dive_apply() -> void:
	var p := TableMotion.ease_out(dive_t / DIVE_SEC)
	camera.zoom = Vector2.ONE * (_dive_z0 * pow(_dive_z1 / _dive_z0, p))
	camera.position = _dive_p0.lerp(_dive_p1, p)
	var a := clampf((dive_t - (DIVE_SEC - DIVE_HUD_SEC)) / DIVE_HUD_SEC, 0.0, 1.0)
	_dive_mod.color = Color(1, 1, 1, a)


## To the end now: the fit, the HUD whole (the end of the time, a tap or key, or a new camera aid).
func dive_finish() -> void:
	if dive_t < 0.0:
		return
	dive_t = -1.0
	camera.zoom = Vector2.ONE * _dive_z1
	camera.position = _dive_p1
	if _dive_mod != null:
		_dive_mod.queue_free()
		_dive_mod = null


# ------------------------------------------------------------- stepping ---

func _process(delta: float) -> void:
	if dive_t >= 0.0:
		dive_t = _dive_hold if _dive_hold >= 0.0 else dive_t + delta
		if dive_t >= DIVE_SEC:
			dive_finish()
		else:
			_dive_apply()
	if _exit_timer > 0.0:
		_exit_timer -= delta
		if _exit_timer <= 0.0 and (coop == null or coop.final_frame >= 0 or coop.ls == null):
			_leave_decided()
		elif _exit_timer <= 0.0:
			_exit_timer = 0.1  # live co-op: wait for the final frame so the result is complete
	if leave_grace > 0.0:
		leave_grace -= delta
	if _undo_t > 0.0:
		_undo_t -= delta
		if _undo_t <= 0.0:
			_undo_refresh_button()
	_place_process()
	if leave_dialog != null and leave_dialog.visible and sim.winner >= 0:
		leave_dialog.visible = false  # (decided meanwhile: the result shows)
	if _end_flow and not _result_shown:
		_end_tick()
	if coop != null:
		_coop_step(delta)
	elif not paused and not _bench_done and not (campaign_mode and sim.ended != 0) and dive_t < 0.0:
		# (A campaign battle stops at its end: the result returned is the
		# state at `ended`.)
		_acc += delta * speed_q / 4.0
		var steps := 0
		while _acc >= TICK_SEC and steps < MAX_TICKS_PER_FRAME and not _bench_done:
			_do_tick()
			_acc -= TICK_SEC
			steps += 1
		if steps == MAX_TICKS_PER_FRAME and _acc >= TICK_SEC:
			_acc = 0.0  # cannot keep up: drop time rather than spiral
		if steps > 0:
			var t0 := Time.get_ticks_usec()
			soldiers.upload()
			_view_tick()
			_upload_ms = (Time.get_ticks_usec() - t0) / 1000.0
	if _au_on and paused:
		AudioFx.fire_level(0.0)
	if coop == null:
		soldiers.set_alpha(clampf(_acc / TICK_SEC, 0.0, 1.0))
	if BoardView.oblique and not BoardView.v3d and city != null and city.kit != null:
		# The oblique view: a wall stretch hiding men close behind it fades while the camera is close (view only).
		var vr := get_viewport_rect().size / camera.zoom
		city.kit.ob_fade_update(camera.zoom.x, Rect2(camera.position - vr * 0.5, vr), player_side)
	_keys_held(delta)
	if view3d != null:
		_v3d_process(delta)
	orders.refresh()  # drop orders the sim has applied
	if paths_on and city != null and (_paths_t < PATHS_FADE_SEC or (city.paths_node != null and city.paths_node.visible)):
		if overlay.preview_on:
			_paths_t = 0.0   # (a route being drawn: the hatch stays)
		else:
			_paths_t += delta
		_paths_apply()
	# Redrawn every frame, paused or not, so order changes show at once.
	overlay.zoom = camera.zoom.x
	trays.zoom = camera.zoom.x
	overlay.append_on = _wp_append() or (Input.is_key_pressed(KEY_SHIFT) and sim.phase == BattleSim.PHASE_BATTLE \
		and not UiScale.is_touch())
	overlay.queue_redraw()

	if bench_mode and not _bench_done:
		_bench_frames.append(delta)
	if _fs_until > 0.0:
		_frame_stats(delta)

	if _tele != null and not _ended:
		_win_frames.append(delta)
		_win_time += delta
		if _win_time >= TELEMETRY_SAMPLE_SEC:
			_send_perf_sample()

	_card_timer -= delta
	if _card_timer <= 0.0:
		_card_timer = 0.25
		hud.update_cards(sim)
		_cg_sync()
		if tutorial != null:
			tutorial.update()
		if coop != null:
			_coop_cards()
		_refresh_actions()
		_update_stats_label()
		_refresh_deploy()


## Testing aid --frame-stats=S: after S seconds (the first 3 skipped) print
## the mean and worst frame time and the time spent in the view's per-tick
## work, then quit.
var _fs_until := 0.0
var _fs_t := 0.0
var _fs_n := 0
var _fs_sum := 0.0
var _fs_max := 0.0


func _frame_stats(delta: float) -> void:
	_fs_t += delta
	if _fs_t < 3.0:
		return
	_fs_n += 1
	_fs_sum += delta
	_fs_max = maxf(_fs_max, delta)
	if _fs_t >= _fs_until:
		print("frame stats: %d frames, mean %.2f ms (%.0f fps), worst %.1f ms; canopy update %d us/tick; trees %d; tick %d%s" % [
			_fs_n, _fs_sum / _fs_n * 1000.0, _fs_n / _fs_sum, _fs_max * 1000.0, trees.update_us, trees.count, sim.tick,
			("; %s view, men ordered in %d us/tick" % ["oblique", soldiers.order_us]) if BoardView.oblique else ""])
		get_tree().quit()


## Woods and settlement views after the sim moved: canopy fade under the
## soldiers, the gates.
func _view_tick() -> void:
	trees.update_occupancy()
	city.refresh()
	works.refresh()
	if ships != null:
		ships.refresh()


func _do_tick() -> void:
	var t0 := Time.get_ticks_usec()
	sim.step()
	_after_tick((Time.get_ticks_usec() - t0) / 1000.0)


## Bookkeeping after the sim stepped (ms: the step's time).
func _after_tick(ms: float) -> void:
	if _au_on:
		_audio_tick()
	_sim_ms.append(ms)
	_win_sim.append(ms)
	if _sim_ms.size() > STATS_WINDOW:
		_sim_ms.remove_at(0)
	if bench_mode:
		_bench_ticks.append(ms)
	if sim.tick % 10 == 0:
		_hash_text = "%08x" % sim.state_hash()
		if sim.tick in HASH_CHECKPOINTS:
			_checkpoint_hashes[str(sim.tick)] = _hash_text
			_t("hash_checkpoint", {"scenario": scenario_id, "seed": seed_value,
				"tick": sim.tick, "hash": _hash_text, "player_orders": _player_orders})
	if sim.tick % 5 == 0 or hud.kill_button.visible:
		_refresh_kill_button()
	var lost := false
	for u in selection:
		if sim.u_state[u] != BattleSim.U_READY:
			lost = true
	if lost:
		_prune_selection()
	elif (sim.city_on != 0 or sim.n_eg > 0) and not selection.is_empty() and sim.tick % 5 == 0:
		_refresh_wall_buttons()  # units walk in and out of reach of a wall, take up or leave engines
	if sim.ended != 0 and not _result_shown and not bench_mode:
		_result_shown = true
		if _au_on:
			AudioFx.play("horn_victory" if sim.winner == player_side else ("horn_start" if sim.winner >= 2 else "horn_defeat"), 0.9, 0.0, "horn")
		var secs: int = maxi(sim.decided_tick, 0) / 10
		hud.banner.visible = false
		if _end_flow:
			_end_finished()
		if not campaign_mode:
			var title := "%s   (decided after %d:%02d)" % [hud.banner.text, secs / 60, secs % 60]
			var dl := destr_line(sim)
			if dl != "":
				title += "\n" + dl
			hud.show_result(sim.result(), title, player_side)
		_t("battle_result", {"scenario": scenario_id, "tick": sim.tick, "result": sim.result()})
		if not custom_summary.is_empty():
			var rs: Dictionary = sim.result()
			_t("custom_battle", {"setup": custom_summary, "winner": sim.winner, "my_side": player_side,
				"online": coop != null, "me": coop.me if coop != null else 0, "tick": sim.tick, "sides": rs["sides"]})
	if sim.winner >= 0 and _decided_tick < 0:
		_decided_tick = sim.tick
		_show_result()
		_t("battle_decided", {"scenario": scenario_id, "tick": sim.tick, "winner": sim.winner,
			"alive0": sim.alive_count(0), "alive1": sim.alive_count(1)})
	if bench_mode and _decided_tick >= 0 and sim.tick >= _decided_tick + 100:
		_finish_bench()


func _update_stats_label() -> void:
	var avg := 0.0
	var worst := 0.0
	for v in _sim_ms:
		avg += v
		worst = maxf(worst, v)
	if _sim_ms.size() > 0:
		avg /= _sim_ms.size()
	var a0 := sim.alive_count(0)
	var a1 := sim.alive_count(1)
	var lim := "no limit" if sim.time_limit >= 360000 else "%d:%02d" % [sim.time_limit / 600, (sim.time_limit / 10) % 60]
	hud.set_stats("%d fps  %d:%02d / %s" % [Engine.get_frames_per_second(), sim.tick / 600, (sim.tick / 10) % 60, lim],
		"FPS %d   sim %.2f ms avg / %.2f worst (2 s)   upload %.2f ms\nsoldiers %d  (%d v %d)   missiles %d   tick %d   hash %s\n%s   seed %d" % [
		Engine.get_frames_per_second(), avg, worst, _upload_ms, a0 + a1, a0, a1,
		sim.projectiles_in_flight(), sim.tick, _hash_text, terrain_name(sim), seed_value])


## "Terrain: Ridge" etc. for the readout and the result.
static func terrain_name(p_sim) -> String:
	if p_sim.ter_on == 0:
		return "Terrain: flat"
	var k: int = p_sim.ter_info.get("kind", 0)
	return "Terrain: %s" % Terrain.KIND_NAMES[k].to_lower()


## The result's line for walls breached and buildings fallen (destruction), "" if none.
static func destr_line(p_sim) -> String:
	if p_sim.city_on == 0 or p_sim.rub_n <= 0:
		return ""
	var parts: Array[String] = []
	if p_sim.stat_breaches > 0:
		parts.append("%d wall stretch%s breached" % [p_sim.stat_breaches, "" if p_sim.stat_breaches == 1 else "es"])
	if p_sim.stat_collapses > 0:
		var bt := "%d building%s fallen" % [p_sim.stat_collapses, "" if p_sim.stat_collapses == 1 else "s"]
		if p_sim.stat_bld_burnt > 0:
			bt += " (%d burnt)" % p_sim.stat_bld_burnt
		parts.append(bt)
	var lost: int = p_sim.stat_breach_kill + p_sim.stat_collapse_kill
	if lost > 0:
		parts.append("%d men lost in the ruins" % lost)
	return ", ".join(parts)


func _show_result() -> void:
	var text := "Draw"
	if sim.winner == 2 and sim.decided_tick >= sim.time_limit:
		text = "Draw: the %d minutes are up" % (sim.time_limit / 600)
	if sim.winner == player_side:
		text = "Victory" if interactive else "Blue wins"
	elif sim.winner == 1 - player_side:
		text = "Defeat" if interactive else "Red wins"
	hud.banner.text = text
	hud.tint_banner(text)
	hud.banner.visible = true
	if _end_choice_open():
		_show_end_dialog(text)  # End battle / Continue; back to the campaign at the end
	elif campaign_mode and not bench_mode:
		_exit_timer = END_BANNER_SEC  # no field result panel: the campaign shows it


func _finish_bench() -> void:
	_bench_done = true
	var ticks := _bench_ticks.duplicate()
	ticks.sort()
	var frames := _bench_frames.duplicate()
	var total := 0.0
	for f in frames:
		total += f
	frames.sort()
	var tsum := 0.0
	for t in ticks:
		tsum += t
	var slow1 := frames[int(frames.size() * 0.99)] if frames.size() > 0 else 0.0
	hud.bench_label.text = "Benchmark: %s\n%d soldiers at start, %d ticks (%.0f s battle time)\n\nSim ms per tick: mean %.2f   p95 %.2f   max %.2f\nFrames: %d, avg %.1f fps, 1%% slowest frame %.1f ms (%.0f fps)\nRenderer: %s\n%s" % [
		Scenarios.title(scenario_id), sim.n, ticks.size(), ticks.size() * TICK_SEC,
		tsum / maxf(1.0, ticks.size()), ticks[int(ticks.size() * 0.95)], ticks[ticks.size() - 1],
		frames.size(), frames.size() / maxf(total, 0.001), slow1 * 1000.0, 1.0 / maxf(slow1, 0.0001),
		RenderingServer.get_video_adapter_name(), OS.get_name() + " " + OS.get_model_name()]
	hud.bench_label.text += "\nMap view: %d trees (built in %.1f ms), canopy update %d us per tick, city %.1f ms, ground %.1f ms" % [
		trees.count, trees.build_ms, trees.update_us, city.build_ms, terrain.build_ms]
	hud.bench_panel.visible = true
	print(hud.bench_label.text)
	_t("bench_summary", {"scenario": scenario_id, "seed": seed_value, "soldiers": sim.n,
		"ticks": ticks.size(), "sim_ms_mean": tsum / maxf(1.0, ticks.size()),
		"sim_ms_p95": ticks[int(ticks.size() * 0.95)], "sim_ms_max": ticks[ticks.size() - 1],
		"frames": frames.size(), "fps_avg": frames.size() / maxf(total, 0.001),
		"frame_ms_p99": slow1 * 1000.0, "frame_ms_max": frames[frames.size() - 1] * 1000.0 if frames.size() > 0 else 0.0,
		"gpu": RenderingServer.get_video_adapter_name(), "text": hud.bench_label.text})
	_end_scenario("bench_complete")


# ------------------------------------------------------------ telemetry ---

## The soldier layer's self-check: pixels drawn around the biggest unit on
## the rendering path in use ("gpu" texture or "cpu" fed; a texture path
## that draws nothing switches to the CPU-fed one and probes again).
func _on_soldier_probe(drawn: int, men: int, path: String) -> void:
	print("SOLDIER_PROBE drawn=%d men=%d path=%s" % [drawn, men, path])
	_t("soldier_probe", {"drawn": drawn, "men": men, "tick": sim.tick, "path": path})


func _t(kind: String, data: Dictionary) -> void:
	if _tele != null:
		_tele.event(kind, data)


func _count(key: String) -> void:
	_input_counts[key] = int(_input_counts.get(key, 0)) + 1


func _reset_window() -> void:
	_win_frames = PackedFloat64Array()
	_win_sim = PackedFloat64Array()
	_win_time = 0.0
	_input_counts = {}
	_orders_by_type = {}


func _send_perf_sample() -> void:
	var frames := _win_frames.duplicate()
	frames.sort()
	var ftotal := 0.0
	for f in frames:
		ftotal += f
	var sims := _win_sim
	var smean := 0.0
	var smax := 0.0
	for v in sims:
		smean += v
		smax = maxf(smax, v)
	if sims.size() > 0:
		smean /= sims.size()
	var nf := frames.size()
	var fmax: float = frames[nf - 1] if nf > 0 else 0.0
	_t("perf", {
		"scenario": scenario_id, "tick": sim.tick, "alive": sim.alive_count(),
		"window_s": _win_time, "frames": nf,
		"fps_avg": nf / maxf(ftotal, 0.001),
		"fps_min": 1.0 / maxf(fmax, 0.0001),
		"frame_ms_p95": (frames[mini(nf - 1, int(nf * 0.95))] * 1000.0) if nf > 0 else 0.0,
		"frame_ms_max": fmax * 1000.0,
		"ticks": sims.size(), "sim_ms_mean": smean, "sim_ms_max": smax,
		"upload_ms": _upload_ms, "speed": speed_q / 4.0, "paused": paused,
		"zoom": camera.zoom.x, "input": _input_counts.duplicate(),
		"orders": _orders_by_type.duplicate(),
	})
	_reset_window()


## Final record for this battle (menu, benchmark complete or node freed).
func _end_scenario(reason: String) -> void:
	if _ended or _tele == null:
		return
	if _win_time > 0.5:
		_send_perf_sample()
	_ended = true
	_t("scenario_end", {"scenario": scenario_id, "seed": seed_value, "reason": reason,
		"soldiers": sim.n, "tick": sim.tick, "winner": sim.winner, "decided_tick": _decided_tick,
		"alive0": sim.alive_count(0), "alive1": sim.alive_count(1),
		"wall_s": (Time.get_ticks_msec() - _start_msec) / 1000.0,
		"final_hash": "%08x" % sim.state_hash(), "checkpoint_hashes": _checkpoint_hashes,
		"player_orders": _player_orders})
	_tele.flush()


## The page is being hidden or closed: the main loop may never run again, so
## record where the battle got to (the run may resume if the tab comes back).
func _on_page_hiding() -> void:
	if _ended:
		return
	if _win_time > 0.5:
		_send_perf_sample()
	_t("scenario_snapshot", {"scenario": scenario_id, "seed": seed_value, "tick": sim.tick,
		"winner": sim.winner, "alive0": sim.alive_count(0), "alive1": sim.alive_count(1),
		"wall_s": (Time.get_ticks_msec() - _start_msec) / 1000.0, "hash": _hash_text,
		"hash_tick": sim.tick - sim.tick % 10, "player_orders": _player_orders})


func _exit_tree() -> void:
	if Tips.presenter == Callable(self, "_show_tip"):
		Tips.presenter = _prev_presenter
	if _au_on:
		_au_on = false
		AudioFx.fire_level(0.0)
		AudioFx.leave_battle()
	_end_scenario("exit")


# --------------------------------------------------------------- orders ---

func _queue(order: Dictionary) -> void:
	if bounds_mode and int(order["type"]) == BattleSim.ORDER_MOVE and BattleSim.stance_ok(sim.u_type[int(order["unit"])]):
		order = order.duplicate()
		order["bound"] = 1
	if sim.phase == BattleSim.PHASE_DEPLOY:
		# Deployment: moves become placements (the same gestures: tap, line,
		# group), everything else that would set the army going waits.
		var typ := int(order["type"])
		if typ == BattleSim.ORDER_MOVE:
			var pu := int(order["unit"])
			var width := int(order.get("width", BattleSim.files_to_width(orders.value(pu, "files"), sim.u_type[pu])))
			order = {"type": BattleSim.ORDER_PLACE, "unit": pu, "x": int(order["x"]), "y": int(order["y"]),
				"facing": int(order["facing"]), "files": BattleSim.width_to_files(width, sim.u_alive[pu], sim.u_type[pu])}
			if selection.size() <= 1 and not BattleSim.place_clear(sim, pu, int(order["x"]), int(order["y"]),
					int(order["facing"]) & 1023, int(order["files"])):
				# (Units do not stand inside each other: the sim refuses it too.)
				_count("place_refused")
				overlay.flash("Another unit stands there", Vector2(int(order["x"]), int(order["y"])) / M * PX_PER_M)
				return
		elif typ != BattleSim.ORDER_RUN and typ != BattleSim.ORDER_FIRE and typ != BattleSim.ORDER_SKIRMISH \
				and typ != BattleSim.ORDER_DEPLOY and typ != BattleSim.ORDER_PLACE and typ != BattleSim.ORDER_READY \
				and typ != BattleSim.ORDER_WORKS and typ != BattleSim.ORDER_DROP \
				and not (typ == BattleSim.ORDER_ABILITY and int(order["state"]) != UT.AB_NOW) \
				and not (typ == BattleSim.ORDER_PICKUP and order.has("equip")):
			_count("order_in_deployment")
			if selected >= 0:
				overlay.flash("Deployment: place your units; orders wait for the battle",
					Vector2(sim.u_cx[selected], sim.u_cy[selected]) / M * PX_PER_M)
			return
	if coop != null:
		# Live co-op: through the lockstep layer, for our own units only.
		if not coop.can_issue():
			return
		var cu := int(order.get("unit", -1))
		if cu >= 0 and not coop.can_order(cu):
			return
		_undo_record(order)
		coop.issue(order)
	else:
		# Solo play: orders apply on the next tick.
		order["tick"] = sim.tick
		_undo_record(order)
		if int(order["type"]) == BattleSim.ORDER_WORKS:
			order["side"] = player_side  # (live: the lockstep sets the issuer's side)
		sim.queue_order(order)
		orders.add(order)
	overlay.queue_redraw()
	if tutorial != null:
		tutorial.seen(order)
	var tname: String = ORDER_NAMES.get(int(order["type"]), "other")
	_player_orders += 1
	_orders_by_type[tname] = int(_orders_by_type.get(tname, 0)) + 1
	if _order_events < MAX_ORDER_EVENTS:
		_order_events += 1
		_t("order", {"type": tname, "tick": sim.tick, "unit": int(order.get("unit", -1)),
			"run": int(order.get("run", 0)), "group": selection.size()})


## A first-time tip (game/campaign/tips.gd) as a card at the top left with a "Got it".
func _show_tip(text: String, _key: String) -> void:
	if _tip_card != null and is_instance_valid(_tip_card):
		hud._ui_controls.erase(_tip_card)
		_tip_card.queue_free()
	var card := TutorCard.new()
	card.name = "tip_card"
	card.setup("", text, "", 360.0)
	card.add_button("got", "Got it")
	card.pressed.connect(func(_k: String):
		hud._ui_controls.erase(card)
		card.queue_free()
		_tip_card = null)
	hud._root.add_child(card)
	hud.add_ui_control(card)
	card.position = Vector2(8.0, hud.top_height() + 6.0)
	_tip_card = card


# ----------------------------------------------------------------- undo ---
# Every order batch the player issues (all the _queue calls of one frame: a
# tap, a line drag, a group move, a bar button, a card order) first records
# each own unit's order as the view predicts it (the sim's fields plus what is
# still queued). Undo pops one batch and re-issues the records as ordinary
# queued orders, so lockstep, replays and hashes never see anything new.

const UNDO_TYPES := [BattleSim.ORDER_MOVE, BattleSim.ORDER_ATTACK, BattleSim.ORDER_HALT, BattleSim.ORDER_RUN,
	BattleSim.ORDER_FIRE, BattleSim.ORDER_SKIRMISH, BattleSim.ORDER_WITHDRAW, BattleSim.ORDER_WITHDRAW_ALL,
	BattleSim.ORDER_DEPLOY, BattleSim.ORDER_REFILL, BattleSim.ORDER_STANCE, BattleSim.ORDER_AMMO,
	BattleSim.ORDER_FORAGE, BattleSim.ORDER_OCCUPY, BattleSim.ORDER_PICKUP]
const UNDO_KEYS := ["order", "face", "files", "dx", "dy", "dface", "target", "run", "fire", "skirm",
	"deploy", "refill", "akind", "forage", "stance", "bound", "gtarget"]
var _undo_stack: Array = []   # batches: {"frame": int, "recs": [record, ...]}
var _undo_t := 0.0            # seconds the Undo button still shows
var _undoing := false


func _undo_record(order: Dictionary) -> void:
	if _undoing or sim.phase != BattleSim.PHASE_BATTLE or not interactive \
			or not UNDO_TYPES.has(int(order["type"])):
		return
	var frame := Engine.get_process_frames()
	var batch: Dictionary = {}
	if not _undo_stack.is_empty() and int((_undo_stack.back() as Dictionary)["frame"]) == frame:
		batch = _undo_stack.back()
	var fresh: Array = []
	for u in BattleSim.order_units(sim, order):
		if sim.u_side[u] != player_side or not _mine(u):
			continue
		var seen := false
		if not batch.is_empty():
			for r in batch["recs"]:
				if int(r["u"]) == u:
					seen = true
		if seen:
			continue
		var rec := {"u": u, "cx": sim.u_cx[u], "cy": sim.u_cy[u], "wp": orders.wp_of(u)}
		for k in UNDO_KEYS:
			rec[k] = orders.value(u, k)
		fresh.append(rec)
	if fresh.is_empty():
		return
	if batch.is_empty():
		batch = {"frame": frame, "recs": [], "name": _undo_batch_name(order)}
		_undo_stack.append(batch)
		while _undo_stack.size() > UNDO_DEPTH:
			_undo_stack.pop_front()
	(batch["recs"] as Array).append_array(fresh)
	_undo_t = UNDO_SHOW_SEC
	_undo_refresh_button()


func _undo_refresh_button() -> void:
	var on := _undo_t > 0.0 and not _undo_stack.is_empty()
	if on and not hud.undo_button.visible:
		_count("undo_shown")
	hud.set_undo_toast(on, _undo_toast_text() if on else "")


## Undo the last order batch: each unit gets its recorded order back.
func _undo() -> void:
	if _undo_stack.is_empty() or not interactive or sim.phase != BattleSim.PHASE_BATTLE:
		return
	var batch: Dictionary = _undo_stack.pop_back()
	_undoing = true
	for r in batch["recs"]:
		_undo_unit(r)
	_undoing = false
	_count("undo")
	if coop_hud != null:
		coop_hud.flash("Order undone", 1.5)
	elif not (batch["recs"] as Array).is_empty():
		var f: int = int((batch["recs"] as Array)[0]["u"])
		overlay.flash("Order undone", Vector2(sim.u_cx[f], sim.u_cy[f]) / M * PX_PER_M)
	_undo_t = UNDO_SHOW_SEC if not _undo_stack.is_empty() else 0.0
	_undo_refresh_button()
	_refresh_actions()


func _undo_unit(r: Dictionary) -> void:
	var u := int(r["u"])
	if sim.u_state[u] != BattleSim.U_READY or not _mine(u):
		return
	# Standing settings first (only those that changed).
	if orders.value(u, "fire") != int(r["fire"]):
		_queue(BattleSim.make_fire_order(0, u, int(r["fire"])))
	if orders.value(u, "skirm") != int(r["skirm"]):
		_queue(BattleSim.make_skirmish_order(0, u, int(r["skirm"])))
	if orders.value(u, "deploy") != int(r["deploy"]):
		_queue(BattleSim.make_deploy_order(0, u, int(r["deploy"])))
	if orders.value(u, "refill") != int(r["refill"]):
		_queue(BattleSim.make_refill_order(0, u, int(r["refill"])))
	if orders.value(u, "akind") != int(r["akind"]):
		_queue({"type": BattleSim.ORDER_AMMO, "unit": u, "on": 1 if int(r["akind"]) != 0 else 0})
	if orders.value(u, "forage") != int(r["forage"]):
		_queue({"type": BattleSim.ORDER_FORAGE, "unit": u, "on": 1 if int(r["forage"]) != 0 else 0})
	if orders.value(u, "stance") != int(r["stance"]):
		_queue({"type": BattleSim.ORDER_STANCE, "unit": u, "stance": int(r["stance"])})
	var run := int(r["run"])
	var files := int(r["files"])
	var width := BattleSim.files_to_width(files, sim.u_type[u])
	var o := int(r["order"])
	if o == BattleSim.O_ATTACK and int(r["target"]) >= 0 and sim.u_state[int(r["target"])] < BattleSim.U_DESTROYED:
		_queue(BattleSim.make_attack_order(0, u, int(r["target"]), run))
	elif o == BattleSim.O_MOVE:
		var mo := BattleSim.make_move_order(0, u, int(r["dx"]), int(r["dy"]), int(r["dface"]), width, run)
		if int(r["bound"]) != 0:
			mo["bound"] = 1
		_queue(mo)
	elif o == BattleSim.O_WITHDRAW:
		_queue(BattleSim.make_withdraw_order(0, u))
	else:
		# It stood without an order (or its target is gone): hold where it was.
		_queue(BattleSim.make_move_order(0, u, int(r["cx"]), int(r["cy"]), int(r["face"]), width, 0))
		if run != 0:
			_queue(BattleSim.make_run_order(0, u, run))
	# Its waypoints after that move, as they were (the queue the sim may have
	# popped meanwhile included).
	_wp_requeue(u, r.get("wp", PackedInt32Array()))


## Deployment phase: this player is ready (solo: the battle starts).
func _deploy_ready() -> void:
	if sim.phase != BattleSim.PHASE_DEPLOY:
		return
	_count("deploy_ready")
	_t("deploy_ready", {"secs_left": sim.deploy_secs_left(), "scenario": scenario_id})
	if coop != null:
		if coop.can_issue():
			coop.issue({"type": BattleSim.ORDER_READY})
		return
	sim.queue_order({"tick": sim.tick, "type": BattleSim.ORDER_READY, "who": 0})
	if paused:
		_toggle_pause()  # a ready player wants the battle to run


## The deployment bar: countdown, who is ready, Start battle / Ready.
func _refresh_deploy() -> void:
	if works != null:
		works.refresh()
	_refresh_works_palette()
	if sim.phase != BattleSim.PHASE_DEPLOY:
		if hud.deploy_panel.visible:
			hud.set_deploy("", "", false)
			_t("battle_start", {"scenario": scenario_id, "tick": sim.tick})
		return
	if interactive and campaign_mode:
		Tips.show("deployment")
	var s: int = sim.deploy_secs_left()
	var text := "Deploying: waiting for players" if s < 0 else "Deployment  %d:%02d" % [s / 60, s % 60]
	if coop != null and coop.ls != null:
		var me_ready := false
		var parts: Array[String] = []
		for p in coop.ls.active_players():
			var r: bool = (sim.dep_ready & (1 << p)) != 0
			if p == coop.me:
				me_ready = r
			elif r:
				parts.append("%s is ready" % coop.player_name(p))
			else:
				parts.append("Waiting for %s" % coop.player_name(p))
		if not parts.is_empty():
			text += "   " + ", ".join(parts)
		hud.set_deploy(text, "Ready" if not me_ready else "Ready: waiting", not me_ready and coop.can_issue())
	else:
		var pend := false
		for o in sim.pending_orders:
			if int(o["type"]) == BattleSim.ORDER_READY:
				pend = true
		hud.set_deploy(text + "   Place your units in the blue zone", "Start battle", not pend and interactive)


const ORDER_NAMES := {BattleSim.ORDER_MOVE: "move", BattleSim.ORDER_ATTACK: "attack",
	BattleSim.ORDER_HALT: "halt", BattleSim.ORDER_RUN: "run", BattleSim.ORDER_FIRE: "fire",
	BattleSim.ORDER_SKIRMISH: "skirmish", BattleSim.ORDER_STANCE: "stance", BattleSim.ORDER_WITHDRAW: "withdraw",
	BattleSim.ORDER_WITHDRAW_ALL: "withdraw_all", BattleSim.ORDER_DEPLOY: "deploy",
	BattleSim.ORDER_REFILL: "refill", BattleSim.ORDER_GATE: "gate", BattleSim.ORDER_PLACE: "place",
	BattleSim.ORDER_READY: "ready", BattleSim.ORDER_AMMO: "ammo", BattleSim.ORDER_FORAGE: "forage",
	BattleSim.ORDER_KILL: "kill", BattleSim.ORDER_RELEASE: "release", BattleSim.ORDER_WORKS: "works",
	BattleSim.ORDER_SABOTAGE: "sabotage", BattleSim.ORDER_ATTEMPT: "attempt", BattleSim.ORDER_PARLEY: "parley",
	BattleSim.ORDER_OCCUPY: "occupy", BattleSim.ORDER_ABILITY: "ability", BattleSim.ORDER_LAND: "land"}


## Select only unit u (-1: clear the selection).
func _select(u: int) -> void:
	selection.clear()
	if u >= 0:
		selection.append(u)
	selected = u
	_selection_changed()


## Add u to the selection, or remove it if it is already in.
func _toggle_in_selection(u: int) -> void:
	if selection.has(u):
		selection.erase(u)
		if selected == u:
			selected = selection[selection.size() - 1] if not selection.is_empty() else -1
	else:
		selection.append(u)
		selected = u
	_selection_changed()


func _prune_selection() -> void:
	var keep: Array[int] = []
	for u in selection:
		if sim.u_state[u] == BattleSim.U_READY and _mine(u):
			keep.append(u)
	selection = keep
	if not selection.has(selected):
		selected = selection[selection.size() - 1] if not selection.is_empty() else -1
	_selection_changed()


func _selection_changed() -> void:
	# Primary first so the overlay knows which unit gets the RUN label.
	var ordered: Array[int] = []
	if selected >= 0:
		ordered.append(selected)
	for u in selection:
		if u != selected:
			ordered.append(u)
	overlay.selected_units = ordered
	if place_on and _place_sel != selection:
		_place_clear()   # (the ghost belongs to the selection it was placed for)
	if occupy_mode:
		_occupy_cancel(false)
	if ability_armed >= 0:
		_ability_cancel(false)
	if waypoint_mode and _wp_sel != selection:
		_count("wp_off_selection")
		_waypoints_off()
	if not selection.is_empty() and paths_on:
		_paths_poke()
	var flags := {}
	for u in selection:
		flags[u] = true
	soldiers.selected_units = flags
	soldiers.upload()
	_refresh_actions()
	overlay.queue_redraw()


## Action button states from the predicted orders of the selection.
## Artillery never runs or skirmishes; only it has the Deploy toggle.
func _refresh_actions() -> void:
	var run := -1
	var fire := -1
	var skirm := -1
	var deploy := -1
	var refill := -1
	var ammo := -1
	var ammo_word := ""
	var forage := -1
	var stance := -1
	var bounds := -1
	var occupy := -1
	for u in selection:
		if BattleSim.stance_ok(sim.u_type[u]):
			if stance < 0:
				stance = orders.value(u, "stance")
			bounds = maxi(bounds, 1 if bounds_mode or orders.value(u, "bound") != 0 else 0)
			if sim.occ_on != 0 and sim.u_state[u] == BattleSim.U_READY:
				occupy = maxi(occupy, 1 if sim.u_occ[u] > 0 or orders.value(u, "occ") != 0 else 0)
		if UT.cls(sim.u_type[u]) == UT.CLS_MISSILE and sim.u_state[u] == BattleSim.U_READY:
			# Refill at a wagon (near one, or doing it); forage (in woods).
			if sim.n_eq > 0 and (sim.wagon_for(u) >= 0 or orders.value(u, "refill") != 0):
				refill = maxi(refill, orders.value(u, "refill"))
			if BattleSim.forage_refusal(sim, u) == "" or orders.value(u, "forage") != 0:
				forage = maxi(forage, orders.value(u, "forage"))
		var sk: int = sim.spec_kind(u)
		if sk >= 0 and sim.u_state[u] == BattleSim.U_READY:
			# A second ammunition kind: the toggle shows what it shoots.
			var on := orders.value(u, "akind")
			if ammo < 0 or on > ammo:
				ammo_word = UT.ammo_text(sk if on != 0 else sim.t_m_ak[sim.u_type[u]], "short")
			ammo = maxi(ammo, on)
			hud.ammo_kinds = [UT.ammo_text(sim.t_m_ak[sim.u_type[u]], "short"), UT.ammo_text(sk, "short")]
		var art := UT.cls(sim.u_type[u]) == UT.CLS_ART
		if not art:
			run = maxi(run, 1 if orders.value(u, "run") != 0 else 0)
		if UT.stat(sim.u_type[u], "m_ammo") > 0:
			fire = maxi(fire, orders.value(u, "fire"))
			if not art:
				skirm = maxi(skirm, orders.value(u, "skirm"))
		if art and UT.stat(sim.u_type[u], "fixed") == 0:
			# (A tower's engine is always set up and has no baggage.)
			deploy = maxi(deploy, orders.value(u, "deploy"))
			refill = maxi(refill, orders.value(u, "refill"))
	if selection.is_empty():
		run = 0
	var dogs := -1
	for u in selection:
		if sim.u_state[u] == BattleSim.U_READY and _pack_ready(u):
			dogs = maxi(dogs, sim.pack_left(u))
	if dogs < 0:
		release_armed = false
	_refresh_char_bar()
	var only_fixed := not selection.is_empty()
	for u in selection:
		if UT.stat(sim.u_type[u], "fixed") == 0 or UT.stat(sim.u_type[u], "ship") != 0:
			only_fixed = false  # (a ship takes orders: fire, attack, Land)
	hud.engine_only = only_fixed
	hud.set_abilities(_ability_info())
	if not selection.is_empty() and sim.phase == BattleSim.PHASE_BATTLE and interactive:
		Tips.show("first_chip")
	hud.chip_mixed = _chip_mixed()
	hud.set_selection(selection, run, fire, skirm, deploy, refill, ammo, ammo_word, forage, dogs, release_armed, stance, bounds, occupy)
	hud.occupy_button.set_pressed_no_signal(occupy_mode and occupy == 0)
	hud.waypoints_button.visible = not selection.is_empty() and not only_fixed and sim.phase == BattleSim.PHASE_BATTLE
	hud.waypoints_button.set_pressed_no_signal(waypoint_mode)
	if occupy_mode and OccView.eligible(sim, selection).is_empty():
		_occupy_cancel(false)
	_sync_occupy_overlay()
	_refresh_wall_buttons()
	if coop != null:
		var tos := _gift_targets()
		hud.gift_button.visible = not selection.is_empty() and not tos.is_empty()
		if tos.size() == 1:
			hud.set_gift_text("Gift to " + coop.player_name(int(tos[0])))
		elif tos.size() > 1:
			hud.set_gift_text("Gift to...")



## Group buttons: every ready player unit of a class.
func _select_group(kind: String) -> void:
	if not interactive:
		return
	_count("group_" + kind)
	selection.clear()
	selected = -1
	# In the card strip's order (the player may have dragged cards around).
	for u in hud.display_order():
		if sim.u_side[u] != player_side or sim.u_state[u] != BattleSim.U_READY or not _mine(u):
			continue
		# The role's filter group (UT.filter_group of the unit's own type: a pack of war dogs let loose stays shock).
		var take := kind == "all" or UT.filter_group(sim.u_type[u]) == kind
		if take:
			selection.append(u)
	if not selection.is_empty():
		selected = selection[0]
	_selection_changed()


# ---- control groups ----

func _cg_units(n: int) -> Array[int]:
	var out: Array[int] = []
	for u in control_groups.get(n, []):
		if u < sim.n_units and sim.u_side[u] == player_side and sim.u_state[u] < BattleSim.U_DESTROYED and _mine(u):
			out.append(u)
	return out


## Drop the units that are gone (destroyed, or left by the edge) from every group, and the groups left empty; the HUD
## and the markers follow when something changed.
func _cg_sync(force := false) -> void:
	var changed := force
	for n in control_groups.keys():
		var keep := _cg_units(n)
		if keep.is_empty():
			control_groups.erase(n)
			changed = true
		elif keep.size() != (control_groups[n] as Array).size():
			control_groups[n] = keep
			changed = true
	if changed:
		hud.set_control_groups(control_groups)
		var tags := {}
		for n in control_groups:
			for u in control_groups[n]:
				tags[u] = hud.card_group_text(u)
		overlay.group_tags = tags
		overlay.queue_redraw()


## Ctrl+digit ("set"), Shift+digit ("add"), the group chip's options ("set", "add", "clear").
func _group_assign(n: int, mode: String) -> void:
	if not interactive or n < 1 or n > 9:
		return
	_count("group_" + mode + "_set")
	if mode == "clear":
		control_groups.erase(n)
	elif selection.is_empty():
		_cg_hint("Select units first", n)
		return
	else:
		var list: Array = (control_groups.get(n, []) as Array).duplicate() if mode == "add" else []
		for u in selection:
			if not list.has(u):
				list.append(u)
		control_groups[n] = list
	_cg_sync(true)
	if control_groups.has(n):
		var k: int = (control_groups[n] as Array).size()
		_cg_hint("Group %d: %d unit%s" % [n, k, "" if k == 1 else "s"], n)


## The "+" chip: the selection becomes the next free group.
func _group_new() -> void:
	for n in range(1, 10):
		if not control_groups.has(n):
			_group_assign(n, "set")
			return


## The digit or the group chip: select group n; the same group again within GROUP_DOUBLE_MS centres the camera on it.
func _group_select(n: int) -> void:
	if not interactive or not control_groups.has(n):
		return
	_cg_sync()
	var members := _cg_units(n)
	if members.is_empty():
		return
	var now := Time.get_ticks_msec()
	var again := n == _cg_last_n and now - _cg_last_ms <= GROUP_DOUBLE_MS
	_cg_last_n = n
	_cg_last_ms = now
	if again:
		_count("group_centre")
		_cam_to(_cg_centre(members))
		return
	_count("group_select")
	selection.clear()
	selected = -1
	for u in members:
		if sim.u_state[u] == BattleSim.U_READY:
			selection.append(u)
	if not selection.is_empty():
		selected = selection[0]
	_selection_changed()
	_cg_hint("Group %d (%d unit%s)" % [n, members.size(), "" if members.size() == 1 else "s"], n)


func _cg_centre(members: Array[int]) -> Vector2:
	var c := Vector2.ZERO
	for u in members:
		c += Vector2(sim.u_cx[u], sim.u_cy[u])
	return c / maxf(members.size(), 1) / M * PX_PER_M


func _cg_hint(text: String, n: int) -> void:
	var members := _cg_units(n)
	var at := _cg_centre(members) if not members.is_empty() else camera.position
	overlay.flash(text, at)


## Unit book over the battle. Solo play: opening it pauses, closing it
## restores the pause state from before.
func _open_book(ty: int, counter: String) -> void:
	_count(counter)
	_t("book_open", {"from": counter, "unit_type": ty, "tick": sim.tick})
	if not hud.book.visible:
		_paused_before_book = paused
		_set_paused(true)
	hud.book.open(ty)
	overlay.preview_on = false
	_dragging = false
	_touches.clear()
	_primary = -1
	_gesture_multi = false


func _on_book_closed() -> void:
	_set_paused(_paused_before_book)


func _set_paused(on: bool) -> void:
	if coop != null:
		return  # co-op: the book and the controls page do not pause the battle
	paused = on
	hud.pause_button.text = "Play" if paused else "Pause"


func _on_card(u: int) -> void:
	if hud.suppress_card == u:
		# Release of a long press that opened the unit book: no selection.
		hud.suppress_card = -1
		_selection_changed()  # undo the card's toggle
		return
	var tg := hud.tower_group(u)
	if interactive and UT.stat(sim.u_type[u], "fixed") != 0 and _mine(u):
		# A wall-engine card: each tap goes on to the next engine of the kind
		# still manned, and the camera goes to it.
		var at := tg.find(selected) if selection.size() == 1 else -1
		var pick := -1
		for k in tg.size():
			var c: int = tg[(at + 1 + k) % tg.size()]
			if sim.u_state[c] == BattleSim.U_READY:
				pick = c
				break
		if pick < 0:
			_selection_changed()
			return
		_select(pick)
		_cam_to(Vector2(sim.u_cx[pick], sim.u_cy[pick]) / M * PX_PER_M)
		return
	if not interactive or sim.u_state[u] != BattleSim.U_READY:
		_selection_changed()  # undo the card's toggle
		return
	if not _mine(u):
		_selection_changed()
		_not_mine_hint(u)
		return
	var add := add_mode or hud.card_mod_add
	_count("card_add" if add else "card_select")
	if add:
		_toggle_in_selection(u)
		return
	if selected == u and selection.size() == 1:
		_select(-1)
	else:
		_select(u)
		_center_on_unit(u)


func _center_on_unit(u: int) -> void:
	var p := BoardView.to_board(Vector2(sim.u_cx[u], sim.u_cy[u]) / M * PX_PER_M)
	var vr := get_viewport_rect().size / camera.zoom
	var cam_rect := Rect2(camera.position - vr * 0.5, vr).grow(-vr.x * 0.1)
	if not cam_rect.has_point(p):
		camera.position = p


func _toggle_pause() -> void:
	_count("pause_toggle")
	if coop != null:
		coop.request_pause()
		return
	paused = not paused
	hud.pause_button.text = "Play" if paused else "Pause"


## The speed slider moved (final: released). Solo it applies at once; in
## co-op the release is a speed vote through lockstep and nothing is
## applied here.
func _on_speed_chosen(q: int, final: bool) -> void:
	if final:
		_count("speed_change")
	if coop != null:
		if final:
			_coop_request_speed(q)
		return
	if q != speed_q:
		speed_q = clampi(q, Lockstep.SPEED_Q_MIN, Lockstep.SPEED_Q_MAX)
		_update_speed_text()


## + / - keys: to the next labelled speed (Hud.SPEED_QS) up / down.
func _step_speed(dir: int) -> void:
	var cur := speed_q
	if coop != null:
		if coop.ls == null:
			return
		cur = coop.ls.vote_speed_q if coop.ls.vote_speed_by == coop.me else coop.ls.speed_q
	var next := cur
	var qs: Array = Hud.SPEED_QS.duplicate()
	if dir < 0:
		qs.reverse()
	for q in qs:
		if (dir > 0 and int(q) > cur) or (dir < 0 and int(q) < cur):
			next = int(q)
			break
	if coop != null:
		_coop_request_speed(next)
	else:
		speed_q = next
		_update_speed_text()


## The HUD's speed: the button shows the speed in force; the slider the
## same, or this player's open co-op proposal.
func _update_speed_text() -> void:
	var q := speed_q
	var sq := q
	if coop != null and coop.ls != null:
		q = coop.ls.speed_q
		sq = coop.ls.vote_speed_q if coop.ls.vote_speed_by == coop.me else q
	_shown_speed = Vector2i(q, sq)
	hud.set_speed(q, sq)


func _toggle_run() -> void:
	if selection.is_empty():
		return
	var any_off := false
	for u in selection:
		if orders.value(u, "run") == 0:
			any_off = true
	for u in selection:
		_queue(BattleSim.make_run_order(0, u, 1 if any_off else 0))
	_refresh_actions()


## The eligible selected units of a two-state chip (the same rule as its toggle), as unit indices.
func _toggle_units(key: String) -> Array[int]:
	var out: Array[int] = []
	for u in selection:
		var ok := false
		match key:
			"run":
				ok = true
			"fire":
				ok = UT.stat(sim.u_type[u], "m_ammo") > 0
			"skirmish":
				ok = _skirmisher(u)
			"bounds":
				ok = BattleSim.stance_ok(sim.u_type[u])
			"deploy":
				ok = UT.cls(sim.u_type[u]) == UT.CLS_ART
			"refill":
				ok = _refiller(u)
			"ammo":
				ok = sim.spec_kind(u) >= 0
			"forage":
				ok = sim.u_state[u] == BattleSim.U_READY and UT.cls(sim.u_type[u]) == UT.CLS_MISSILE \
					and (BattleSim.forage_refusal(sim, u) == "" or orders.value(u, "forage") != 0)
		if ok:
			out.append(u)
	return out


## A unit's predicted value (0 / 1) of a two-state chip.
func _toggle_val(key: String, u: int) -> int:
	match key:
		"run": return 1 if orders.value(u, "run") != 0 else 0
		"fire": return 1 if orders.value(u, "fire") != 0 else 0
		"skirmish": return 1 if orders.value(u, "skirm") != 0 else 0
		"bounds": return 1 if bounds_mode or orders.value(u, "bound") != 0 else 0
		"deploy": return 1 if orders.value(u, "deploy") != 0 else 0
		"refill": return 1 if orders.value(u, "refill") != 0 else 0
		"ammo": return 1 if orders.value(u, "akind") != 0 else 0
		"forage": return 1 if orders.value(u, "forage") != 0 else 0
	return 0


## Chip key -> true where the eligible selected units disagree (the chip reads "mixed").
func _chip_mixed() -> Dictionary:
	var out := {}
	for key in ["run", "fire", "skirmish", "bounds", "deploy", "refill", "ammo", "forage"]:
		var seen := 0
		for u in _toggle_units(key):
			seen |= 1 << _toggle_val(key, u)
		if seen == 3:
			out[key] = true
	return out


## A row of a two-state chip's options: SET `value` on every eligible selected unit (the keyboard / one-tap
## toggles above still flip). Units already there get no order.
func _set_toggle(key: String, value: int) -> void:
	var v := 1 if value != 0 else 0
	if key == "bounds":
		bounds_mode = v == 1   # (a mode for the next move orders, as _toggle_bounds)
		_refresh_actions()
		return
	for u in _toggle_units(key):
		if _toggle_val(key, u) == v:
			continue
		match key:
			"run": _queue(BattleSim.make_run_order(0, u, v))
			"fire": _queue(BattleSim.make_fire_order(0, u, v))
			"skirmish": _queue(BattleSim.make_skirmish_order(0, u, v))
			"deploy": _queue(BattleSim.make_deploy_order(0, u, v))
			"refill": _queue(BattleSim.make_refill_order(0, u, v))
			"ammo": _queue({"type": BattleSim.ORDER_AMMO, "unit": u, "on": v})
			"forage": _queue({"type": BattleSim.ORDER_FORAGE, "unit": u, "on": v})
	if key == "ammo":
		_count("ammo")
	elif key == "forage":
		_count("forage")
	_refresh_actions()


func _halt() -> void:
	for u in selection:
		_queue(BattleSim.make_halt_order(0, u))


## Fire at will on/off for the missile units in the selection.
func _toggle_fire() -> void:
	var any_on := false
	for u in selection:
		if UT.stat(sim.u_type[u], "m_ammo") > 0 and orders.value(u, "fire") != 0:
			any_on = true
	for u in selection:
		if UT.stat(sim.u_type[u], "m_ammo") > 0:
			_queue(BattleSim.make_fire_order(0, u, 0 if any_on else 1))
	_refresh_actions()


func _toggle_skirmish() -> void:
	var any_on := false
	for u in selection:
		if _skirmisher(u) and orders.value(u, "skirm") != 0:
			any_on = true
	for u in selection:
		if _skirmisher(u):
			_queue(BattleSim.make_skirmish_order(0, u, 0 if any_on else 1))
	_refresh_actions()


## Stance button: Line -> Take cover -> Hold street -> Line, from the first
## eligible selected unit's predicted stance, for every eligible unit.
func _cycle_stance() -> void:
	var nxt := -1
	for u in selection:
		if BattleSim.stance_ok(sim.u_type[u]):
			nxt = (orders.value(u, "stance") + 1) % 3
			break
	if nxt < 0:
		return
	_set_stance(nxt)


## The Stance chip's options: every eligible selected unit takes stance `nxt` (0 Line, 1 Cover, 2 Hold street).
func _set_stance(nxt: int) -> void:
	for u in selection:
		if BattleSim.stance_ok(sim.u_type[u]):
			_queue({"type": BattleSim.ORDER_STANCE, "unit": u, "stance": nxt})
	_refresh_actions()


## Occupy (West towns, slice 2c; the pick flow 2026-10-22). With none of the
## selection in a building: the button arms the mode, every building the
## selected foot may be sent into lights up (OccView.lit, the sim's own
## rule), a mouse hover or a first touch tap on a lit one shows its sight
## fans and places, a click or a second tap sends the men in (the nearest man
## to its door; the others to the nearest free lit building within
## OCC_PICK_R, none picked twice); a tap elsewhere, Esc, the button again or
## another selection cancels. When one of them holds a building or is on its
## way in, the button is Leave: all of them out (a move 8 m out from the
## door, facing out).
const OCC_PICK_R := 60 * 1024
var occupy_mode := false       # the Occupy button is armed: the lit buildings wait for a pick
var _occ_lit: Array[int] = []

func _toggle_occupy() -> void:
	if sim.occ_on == 0:
		return
	var out := false
	for u in selection:
		if BattleSim.stance_ok(sim.u_type[u]) and (sim.u_occ[u] > 0 or orders.value(u, "occ") != 0):
			out = true
	if out:
		_occupy_cancel(false)
		_occupy_leave()
		return
	if occupy_mode:
		_occupy_cancel(true)
		return
	var lit := OccView.lit(sim, selection)
	if lit.is_empty():
		if selected >= 0:
			overlay.flash("No building here can be held by them", Vector2(sim.u_cx[selected], sim.u_cy[selected]) / M * PX_PER_M)
		return
	occupy_mode = true
	_occ_lit = lit
	overlay.occ_mode = true
	overlay.occ_lit = lit
	overlay.occ_focus = -1
	overlay.occ_hint = ""
	overlay.occ_range_m = OccView.range_m(sim, selected)
	_count("occupy_arm")
	_refresh_actions()
	overlay.queue_redraw()


## Leave the armed Occupy mode (counter occupy_cancel when the player did).
func _occupy_cancel(counted: bool) -> void:
	if not occupy_mode:
		return
	occupy_mode = false
	_occ_lit = []
	overlay.occ_mode = false
	overlay.occ_lit = []
	overlay.occ_focus = -1
	overlay.occ_hint = ""
	if counted:
		_count("occupy_cancel")
	_sync_occupy_overlay()
	_refresh_actions()
	overlay.queue_redraw()


## The shown building: the armed mode's pick (set by hover / first tap), else the building the selected unit holds.
func _sync_occupy_overlay() -> void:
	if occupy_mode or sim.occ_on == 0:
		return
	var f := -1
	if selected >= 0 and selected < sim.n_units and sim.u_occ[selected] > 0:
		f = sim.u_occ[selected] - 1
	if f != overlay.occ_focus:
		overlay.occ_focus = f
		overlay.occ_hint = ""
		if f >= 0:
			overlay.occ_range_m = OccView.range_m(sim, selected)
		overlay.queue_redraw()


## The men out of their buildings: a move 8 m out from the door, facing out.
func _occupy_leave() -> void:
	for u in selection:
		if not BattleSim.stance_ok(sim.u_type[u]) or sim.u_state[u] != BattleSim.U_READY:
			continue
		var b: int = sim.u_occ[u] - 1
		if b < 0:
			b = orders.value(u, "occ") - 1
		if b < 0:
			continue
		var f: int = sim.ob_face[b]
		var x: int = sim.ob_dx[b] + FM.cos_a(f) * 8 * 1024 / FM.TRIG_ONE
		var y: int = sim.ob_dy[b] + FM.sin_a(f) * 8 * 1024 / FM.TRIG_ONE
		_queue(BattleSim.make_move_order(0, u, x, y, f, BattleSim.files_to_width(mini(sim.u_alive[u], 10), sim.u_type[u]),
			orders.value(u, "run")))
	_refresh_actions()


## The lit building under world point w (px): inside its footprint, or its door step, or within the
## marker's hit radius of its middle; the nearest middle wins. -1: none.
func _occupy_building_at(w: Vector2) -> int:
	var p := w / PX_PER_M
	var best := -1
	var bd := 1e18
	var hit_r := float(_marker_hit_r()) / M
	for b in _occ_lit:
		var q := OccView.quad(sim, b)
		if q.size() < 4:
			continue
		var mid := (q[0] + q[1] + q[2] + q[3]) * 0.25
		var dstep := p.distance_to(Vector2(sim.ob_dx[b], sim.ob_dy[b]) / M)
		if Geometry2D.is_point_in_polygon(p, q) or dstep < 2.5 or p.distance_to(mid) < minf(hit_r, 6.0):
			var d := p.distance_squared_to(mid)
			if d < bd:
				bd = d
				best = b
	return best


## Show building b's fans (b < 0: none) with the line saying what the next tap / click does.
func _occupy_focus(b: int, hint: String) -> void:
	if b != overlay.occ_focus:
		if b >= 0:
			_count("occupy_preview")
		overlay.occ_focus = b
	overlay.occ_hint = hint if b >= 0 else ""
	overlay.queue_redraw()


## A tap while the Occupy mode is armed (touch: the first tap on a lit building shows it, the second
## sends the men in; the mouse's click does at once, the hover having shown it).
func _occupy_tap(w: Vector2) -> void:
	var b := _occupy_building_at(w)
	if b < 0:
		_occupy_cancel(true)
		return
	if UiScale.is_touch() and overlay.occ_focus != b:
		_occupy_focus(b, "Tap again to send them in")
		return
	_occupy_send(b)


## Send the selection into building b: the man nearest its door in, the others each to the nearest free
## lit building within OCC_PICK_R.
func _occupy_send(b: int) -> void:
	var taken := {b: true}
	var first := -1
	var fd := 1 << 60
	for u in selection:
		if BattleSim.occupy_refusal(sim, u, b) != "":
			continue
		var d := FM.approx_len(sim.ob_dx[b] - sim.u_ax[u], sim.ob_dy[b] - sim.u_ay[u])
		if d < fd:
			fd = d
			first = u
	if first < 0:
		overlay.flash("They cannot hold that building", Vector2(sim.ob_dx[b], sim.ob_dy[b]) / M * PX_PER_M)
		return
	var sent := [first]
	_queue({"type": BattleSim.ORDER_OCCUPY, "unit": first, "building": b, "run": orders.value(first, "run")})
	for u in selection:
		if u == first or not BattleSim.stance_ok(sim.u_type[u]) or sim.u_state[u] != BattleSim.U_READY:
			continue
		var best := -1
		var bd := OCC_PICK_R + 1
		for k in _occ_lit:
			if taken.has(k) or BattleSim.occupy_refusal(sim, u, k) != "":
				continue
			var d2 := FM.approx_len(sim.ob_dx[k] - sim.u_ax[u], sim.ob_dy[k] - sim.u_ay[u])
			if d2 < bd:
				bd = d2
				best = k
		if best >= 0:
			taken[best] = true
			sent.append(u)
			_queue({"type": BattleSim.ORDER_OCCUPY, "unit": u, "building": best, "run": orders.value(u, "run")})
	_count("occupy_pick")
	_occupy_cancel(false)


# ------------------------------------------------------- ability chips ---
# The bar's ability chips (docs/design/ui.md "The battle HUD pass"): Auto -> Hold -> Use now -> Auto per ability of
# the selected units' roles (UT.abilities; Pistols only Auto <-> Hold; the Countermarch's Use now takes no target). Auto and Hold are one ORDER_ABILITY per unit
# through _queue; Use now arms a target pick on the field (as Occupy arms its building pick) and the tap sends the
# order with its target (grenades: an enemy unit or a shut gate; caracole: an enemy unit; batter: a wall stretch, a
# gate or a building). Nothing here touches the sim except by orders.
const AB_ICONS := ["pistol", "grenade", "caracole", "target", "countermarch"]
const AB_PRED_TICKS := 40      # a predicted state is trusted this long past its order's tick
var ability_armed := -1        # the UT.AB_* waiting for its target (-1 none)
var _ab_pred := {}             # unit * 8 + ability -> [state, tick queued]: what the chip shows before the sim applies it
var _ab_lit: Array[int] = []   # a batter pick: the standing buildings lit for it


## The selected units that have ability ab and may take its order.
func _ability_units(ab: int) -> Array[int]:
	var out: Array[int] = []
	for u in selection:
		if sim.u_state[u] != BattleSim.U_READY or not _mine(u):
			continue
		if BattleSim.ability_refusal(sim, u, ab, UT.AB_AUTO) != "":
			continue
		if ab == UT.AB_BATTER and (sim.city_on == 0 or sim.u_side[u] == sim.city_def):
			continue
		out.append(u)
	return out


## Unit u's state of ability ab as the player should see it: a just-ordered one before the sim has applied it.
func _ab_state(u: int, ab: int) -> int:
	var k := u * 8 + ab
	if _ab_pred.has(k):
		var pr: Array = _ab_pred[k]
		if sim.ability_state(u, ab) == int(pr[0]) or sim.tick > int(pr[1]) + AB_PRED_TICKS:
			_ab_pred.erase(k)
		else:
			return int(pr[0])
	return sim.ability_state(u, ab)


## The chips' info for the HUD: UT.AB_* -> {"word", "armed"} for each ability some selected unit has.
func _ability_info() -> Dictionary:
	var info := {}
	for ab in UT.AB_N:
		var us := _ability_units(ab)
		if us.is_empty():
			continue
		var seen := {}
		for u in us:
			seen[_ab_state(u, ab)] = true
		var word := "Mixed"
		if seen.size() == 1:
			word = UT.AB_STATE_NAMES[int(seen.keys()[0])]
		info[ab] = {"word": "Use now" if ability_armed == ab else word, "armed": ability_armed == ab}
	return info


func _queue_ability(u: int, ab: int, st: int, tgt: int) -> void:
	_queue(BattleSim.make_ability_order(0, u, ab, st, tgt))
	_ab_pred[u * 8 + ab] = [st, sim.tick]


## An ability chip was tapped: cycle its state; Use now arms the pick. (The bar's chips no longer cycle: a tap opens
## the options and a row calls _ability_set; this stays for the armed chip tapped again, which cancels.)
func _ability_pressed(ab: int) -> void:
	if not interactive:
		return
	if ability_armed == ab:
		_ability_cancel(true)
		return
	var us := _ability_units(ab)
	if us.is_empty():
		return
	_ability_set(ab, (_ab_state(us[0], ab) + 1) % 3)


## A row of an ability chip's options: set the state `nxt` (Auto / Hold / Use now) for the selected units that have it.
func _ability_set(ab: int, nxt: int) -> void:
	if not interactive:
		return
	if ability_armed >= 0:
		_ability_cancel(true)   # (back to Auto; a row other than Auto then sets its own state)
	var us := _ability_units(ab)
	if us.is_empty():
		return
	if nxt == UT.AB_NOW and ab == UT.AB_PISTOL:
		nxt = UT.AB_AUTO   # (no target to give a brace of pistols)
	if nxt == UT.AB_NOW and sim.phase != BattleSim.PHASE_BATTLE:
		nxt = UT.AB_AUTO
		overlay.flash("Use now: not before the battle starts", Vector2(sim.u_cx[us[0]], sim.u_cy[us[0]]) / M * PX_PER_M)
	if nxt == UT.AB_NOW and ab != UT.AB_ROLL:
		_ability_arm(ab, us)
		return   # (the countermarch's Use now has no target: rolling fire at any range, set at once)
	for u in us:
		_queue_ability(u, ab, nxt, -1)
	_count("ability_%s_%s" % [UT.AB_NAMES[ab].to_lower(), UT.AB_STATE_NAMES[nxt].to_lower().replace(" ", "_")])
	_refresh_actions()


func _ability_arm(ab: int, us: Array[int]) -> void:
	ability_armed = ab
	var hint := {UT.AB_GRENADE: "Tap an enemy unit or a shut gate to throw at", UT.AB_CARACOLE: "Tap an enemy unit to caracole at",
		UT.AB_BATTER: "Tap a wall stretch, a gate or a building to batter (torch raiders: a gate or a palisade stretch)"}
	_count("ability_arm_" + UT.AB_NAMES[ab].to_lower())
	var lit: Array[int] = []
	if ab == UT.AB_BATTER:
		for b in sim.ob_state.size():
			if sim.ob_state[b] == BattleSim.WS_STANDING:
				lit.append(b)
		_ab_lit = lit
		overlay.occ_mode = true
		overlay.occ_lit = lit
		overlay.occ_focus = -1
	else:
		var tl: Array[int] = []
		for t in sim.n_units:
			if sim.u_side[t] != player_side and sim.u_state[t] < BattleSim.U_DESTROYED:
				tl.append(t)
		overlay.target_lit = tl
	overlay.flash(str(hint.get(ab, "Tap a target")), Vector2(sim.u_cx[us[0]], sim.u_cy[us[0]]) / M * PX_PER_M)
	_refresh_actions()
	overlay.queue_redraw()


## Leave the armed pick; counted (Esc, the chip again): the units go back to Auto.
func _ability_cancel(counted: bool) -> void:
	var ab := ability_armed
	if ab < 0:
		return
	ability_armed = -1
	_ab_lit = []
	overlay.target_lit = []
	if overlay.occ_mode and not occupy_mode:
		overlay.occ_mode = false
		overlay.occ_lit = []
	if counted:
		_count("ability_cancel")
		for u in _ability_units(ab):
			if _ab_state(u, ab) != UT.AB_AUTO:
				_queue_ability(u, ab, UT.AB_AUTO, -1)
	_refresh_actions()
	overlay.queue_redraw()


## The armed pick on what is under w (world px).
func _ability_tap(w: Vector2) -> void:
	var ab := ability_armed
	var tgt := -999
	var tgm := -999  # (the batter's melee form, native siege: a gate -2 - g or a wall stretch)
	var p := w / PX_PER_M
	var t := _pick_unit(w)
	var enemy := t >= 0 and sim.u_side[t] != player_side and sim.u_state[t] < BattleSim.U_DESTROYED
	match ab:
		UT.AB_GRENADE:
			if enemy:
				tgt = t
			elif sim.city_on != 0 and _gate_at(w) >= 0:
				tgt = -2 - _gate_at(w)
		UT.AB_CARACOLE:
			if enemy:
				tgt = t
		UT.AB_BATTER:
			var b := _ab_building_at(p)
			var gw := _gate_at(w) if sim.city_on != 0 else -1
			var sg := BattleSim.wall_stretch_at(sim, int(p.x * M), int(p.y * M))
			if b >= 0:
				tgt = -2 - b
			elif gw >= 0:
				tgt = -1   # (the stretch the destruction AI batters by that gate)
			elif sg >= 0:
				tgt = sg
			if gw >= 0:
				tgm = -2 - gw
			elif sg >= 0 and b < 0:
				tgm = sg
	if tgt == -999 and tgm == -999:
		_count("ability_pick_miss")
		overlay.flash("Not a target for it (Esc cancels)", w)
		return
	var sent := 0
	var why := ""
	for u in _ability_units(ab):
		var r := BattleSim.ability_refusal(sim, u, ab, UT.AB_NOW)
		var tu := tgm if ab == UT.AB_BATTER and sim.t_mbat[sim.u_type[u]] != 0 else tgt
		if r == "" and tu == -999:
			r = "torch raiders batter a gate or a palisade stretch"
		if r != "":
			why = r
			continue
		_queue_ability(u, ab, UT.AB_NOW, tu)
		sent += 1
	_count("ability_use_" + UT.AB_NAMES[ab].to_lower())
	ability_armed = -1
	_ab_lit = []
	overlay.target_lit = []
	if overlay.occ_mode and not occupy_mode:
		overlay.occ_mode = false
		overlay.occ_lit = []
	overlay.flash("%s: Use now" % ("Target" if ab == UT.AB_BATTER else UT.AB_NAMES[ab]) if sent > 0 else "Cannot: " + why, w)
	_refresh_actions()
	overlay.queue_redraw()


## The lit (standing) building under p (metres), -1 none.
func _ab_building_at(p: Vector2) -> int:
	var best := -1
	var bd := 1e18
	var hit_r := minf(float(_marker_hit_r()) / M, 6.0)
	for b in _ab_lit:
		var q := OccView.quad(sim, b)
		if q.size() < 4:
			continue
		var mid := (q[0] + q[1] + q[2] + q[3]) * 0.25
		if Geometry2D.is_point_in_polygon(p, q) or p.distance_to(mid) < hit_r:
			var d := p.distance_squared_to(mid)
			if d < bd:
				bd = d
				best = b
	return best


## The card's state strip: [glyph, word] for each chip of unit u not at its default (the HUD draws and tips them).
## Glyph "icon" a state, "icon!" an ability on Hold, "icon*" a Use now (or its pick armed).
func _card_states(u: int) -> Array:
	var out := []
	if sim.u_state[u] != BattleSim.U_READY or sim.u_side[u] != player_side:
		return out
	var ty: int = sim.u_type[u]
	# Suppression (2026-11-06, docs/design/ui.md "Suppression chips"): first, it changes what the unit can do.
	var sus: int = sim.supp_state(u)
	if sus == BattleSim.SUP_PIN:
		out.append(["pinned", "Pinned"])
	elif sus == BattleSim.SUP_SUPP:
		out.append(["suppressed", "Suppressed"])
	if UT.stat(ty, "m_ammo") > 0 and orders.value(u, "fire") == 0:
		out.append(["hold_fire", "Fire: hold"])
	if BattleSim.stance_ok(ty):
		var dflt := BattleSim.STANCE_COVER if sim.t_cover[ty] != 0 else BattleSim.STANCE_LINE
		var stn: int = orders.value(u, "stance")
		if stn != dflt:
			if stn == BattleSim.STANCE_COVER:
				out.append(["stance_cover", "Stance: Cover"])
			elif stn == BattleSim.STANCE_HOLD:
				out.append(["stance_hold", "Stance: Hold street"])
			else:
				out.append(["stance_line", "Stance: Line"])
	if sim.t_abil[ty] != 0:
		for ab in UT.AB_N:
			if (sim.t_abil[ty] & (1 << ab)) == 0:
				continue
			var st := _ab_state(u, ab)
			var nm: String = UT.AB_NAMES[ab]
			if ability_armed == ab and selection.has(u):
				out.append(["target*", "%s: Use now, waiting for a target" % nm])
			elif st == UT.AB_HOLD:
				out.append([str(AB_ICONS[ab]) + "!", "%s: Hold" % nm])
			elif st == UT.AB_NOW:
				out.append(["target*", "%s: Use now" % nm])
	return out


## Bounds: a view-side mode that adds "bound" to the player's move orders.
# ------------------------------------------------------------ waypoints ---
# docs/DESIGN.md "Waypoints": a move given with "append" 1 goes after the
# unit's current move (the sim's queue, BattleSim.WP_MAX stops). Touch: the
# Waypoints toggle on the command bar (off by itself when the selection
# changes, or a two-finger tap); mouse: Shift + right click / right drag.
# A stop is taken out by re-issuing the chain without it (ordinary orders:
# the sim has no "remove", so lockstep and Undo see nothing new).

var waypoint_mode := false
var _wp_sel: Array[int] = []   # the selection the toggle was turned on for


func _toggle_waypoints() -> void:
	if not interactive:
		return
	if waypoint_mode:
		_count("wp_off")
		_waypoints_off()
		return
	waypoint_mode = true
	_wp_sel = selection.duplicate()
	_count("wp_on")
	_t("wp_toggle", {"on": 1, "group": selection.size()})
	if selected >= 0:
		overlay.flash("Waypoints: each tap adds a stop", Vector2(sim.u_cx[selected], sim.u_cy[selected]) / M * PX_PER_M)
	_refresh_actions()


func _waypoints_off() -> void:
	if not waypoint_mode:
		return
	waypoint_mode = false
	_refresh_actions()


## Moves issued now add a waypoint (the toggle, or Shift at a right press).
func _wp_append() -> bool:
	if sim == null or sim.phase != BattleSim.PHASE_BATTLE:
		return false
	return waypoint_mode or _rmb_shift


## Queue move `mo` as a waypoint (at most WP_MAX a unit; at_px: where to
## flash the stop's number).
func _wp_queue_append(mo: Dictionary, at_px: Vector2) -> void:
	var u := int(mo["unit"])
	if orders.wp_of(u).size() >= BattleSim.WP_MAX * BattleSim.WP_K:
		_count("wp_full")
		overlay.flash("At most %d waypoints" % BattleSim.WP_MAX, at_px)
		return
	mo["append"] = 1
	_queue(mo)
	_count("wp_append")
	if u == selected:
		var n := orders.chain(u).size()
		overlay.flash("Waypoint %d" % n if n > 0 else "Move", at_px)


## The second tap of a double tap while adding waypoints: the stop the
## first tap added (the last) is run to.
func _wp_last_run(u: int) -> void:
	var q := orders.wp_of(u)
	if q.is_empty():
		if orders.value(u, "order") == BattleSim.O_MOVE and orders.value(u, "run") == 0 \
				and UT.cls(sim.u_type[u]) != UT.CLS_ART:
			_queue(BattleSim.make_run_order(0, u, 1))
		return
	if (q[q.size() - 1] & BattleSim.WP_ATTACK) != 0:
		return   # (the last point is an attack: it runs by its own double tap)
	var nq := q.duplicate()
	nq[nq.size() - 1] = nq[nq.size() - 1] | BattleSim.WP_RUN
	_count("wp_run")
	_wp_reissue(u, nq, false)


## Re-issue unit u's chain: its current move (or, drop_current, the first
## waypoint as the move), then the waypoints `q` appended.
func _wp_reissue(u: int, q: PackedInt32Array, drop_current: bool) -> void:
	var K := BattleSim.WP_K
	if drop_current:
		if q.is_empty():
			_queue(BattleSim.make_halt_order(0, u))
			return
		if (q[4] & BattleSim.WP_ATTACK) != 0:
			_queue(BattleSim.make_attack_order(0, u, q[0], 1 if (q[4] & BattleSim.WP_RUN) != 0 else 0))   # (only the attack was left)
			return
		var m0 := BattleSim.make_move_order(0, u, q[0], q[1], q[2], q[3], 1 if (q[4] & BattleSim.WP_RUN) != 0 else 0)
		if (q[4] & BattleSim.WP_BOUND) != 0:
			m0["bound"] = 1
		_queue(m0)
		_wp_requeue(u, q.slice(K))
		return
	var mo := BattleSim.make_move_order(0, u, orders.value(u, "dx"), orders.value(u, "dy"), orders.value(u, "dface"),
		BattleSim.files_to_width(orders.value(u, "files"), sim.u_type[u]), orders.value(u, "run"))
	if orders.value(u, "bound") != 0:
		mo["bound"] = 1
	_queue(mo)
	_wp_requeue(u, q)


## Append the waypoints q (WP_K values each) to unit u's orders.
func _wp_requeue(u: int, q: PackedInt32Array) -> void:
	var K := BattleSim.WP_K
	for i in q.size() / K:
		var k := i * K
		var o := BattleSim.make_move_order(0, u, q[k], q[k + 1], q[k + 2], q[k + 3], 1 if (q[k + 4] & BattleSim.WP_RUN) != 0 else 0)
		if (q[k + 4] & BattleSim.WP_ATTACK) != 0:
			o = BattleSim.make_attack_order(0, u, q[k], 1 if (q[k + 4] & BattleSim.WP_RUN) != 0 else 0)   # (the attack ending the chain)
		o["append"] = 1
		if (q[k + 4] & BattleSim.WP_BOUND) != 0:
			o["bound"] = 1
		_queue(o)


## The waypoint dot of a selected unit's chain under world point w (px):
## (unit, stop index; 0 the current move's destination), (-1, -1) none.
func _wp_dot_at(w: Vector2) -> Vector2i:
	var r: float = overlay.chain_dot_r() * (2.0 if UiScale.is_touch() else 1.4)
	var best := Vector2i(-1, -1)
	var bd := r
	for u in selection:
		var ch: Array = orders.chain(u)
		for i in ch.size():
			var at: Vector2i = (ch[i] as Dictionary)["at"]
			var dd := (Vector2(at) / M * PX_PER_M).distance_to(w)
			if dd <= bd:
				bd = dd
				best = Vector2i(u, i)
	return best


## Take stop `idx` out of unit u's chain (0: the current move's destination;
## the unit goes on to the next).
func _wp_remove(u: int, idx: int) -> void:
	var q := orders.wp_of(u)
	var ch: Array = orders.chain(u)
	var at_px := Vector2((ch[idx] as Dictionary)["at"]) / M * PX_PER_M if idx < ch.size() else Vector2.ZERO
	if idx == 0:
		_wp_reissue(u, q, true)
	else:
		var k := (idx - 1) * BattleSim.WP_K
		var nq := q.slice(0, k)
		nq.append_array(q.slice(k + BattleSim.WP_K))
		_wp_reissue(u, nq, false)
	_count("wp_remove")
	overlay.flash("Waypoint %d removed" % (idx + 1), at_px)


func _toggle_bounds() -> void:
	var on := bounds_mode
	if not on:
		for u in selection:
			if BattleSim.stance_ok(sim.u_type[u]) and orders.value(u, "bound") != 0:
				on = true
	bounds_mode = not on
	_refresh_actions()


func _skirmisher(u: int) -> bool:
	return UT.stat(sim.u_type[u], "m_ammo") > 0 and UT.cls(sim.u_type[u]) != UT.CLS_ART


## Artillery in the selection: pack up if any battery wants to be set up,
## otherwise set them all up.
func _toggle_deploy() -> void:
	var any_on := false
	for u in selection:
		if UT.cls(sim.u_type[u]) == UT.CLS_ART and orders.value(u, "deploy") != 0:
			any_on = true
	for u in selection:
		if UT.cls(sim.u_type[u]) == UT.CLS_ART:
			_queue(BattleSim.make_deploy_order(0, u, 0 if any_on else 1))
	_refresh_actions()


## Units with a special ammunition kind in the selection: back to the
## standard kind if any shoots its special one, otherwise all to the special.
func _toggle_ammo() -> void:
	var any_on := false
	for u in selection:
		if sim.spec_kind(u) >= 0 and orders.value(u, "akind") != 0:
			any_on = true
	for u in selection:
		if sim.spec_kind(u) >= 0:
			_queue({"type": BattleSim.ORDER_AMMO, "unit": u, "on": 0 if any_on else 1})
	_count("ammo")
	_refresh_actions()


## Artillery in the selection: stop refilling if any battery is, otherwise
## start refilling them all.
func _toggle_refill() -> void:
	var any_on := false
	for u in selection:
		if _refiller(u) and orders.value(u, "refill") != 0:
			any_on = true
	for u in selection:
		if _refiller(u):
			_queue(BattleSim.make_refill_order(0, u, 0 if any_on else 1))
	_refresh_actions()


## Unit u can be told to refill: a battery (its baggage, or a wagon near),
## or missile troops with an ammunition wagon near (or refilling now).
func _refiller(u: int) -> bool:
	var c := UT.cls(sim.u_type[u])
	if c == UT.CLS_ART:
		return UT.stat(sim.u_type[u], "fixed") == 0
	return c == UT.CLS_MISSILE and sim.n_eq > 0 and (sim.wagon_for(u) >= 0 or orders.value(u, "refill") != 0)


## Missile troops in woods in the selection: stop foraging if any is,
## otherwise start (those that can).
func _toggle_forage() -> void:
	var any_on := false
	for u in selection:
		if orders.value(u, "forage") != 0:
			any_on = true
	var sent := 0
	var why := ""
	for u in selection:
		if any_on:
			if orders.value(u, "forage") != 0:
				_queue({"type": BattleSim.ORDER_FORAGE, "unit": u, "on": 0})
			continue
		var r: String = BattleSim.forage_refusal(sim, u)
		if r == "":
			_queue({"type": BattleSim.ORDER_FORAGE, "unit": u, "on": 1})
			sent += 1
		elif why == "":
			why = r
	_count("forage")
	if not any_on and sent == 0 and why != "" and selected >= 0:
		overlay.flash(why, Vector2(sim.u_cx[selected], sim.u_cy[selected]) / M * PX_PER_M)
	_refresh_actions()


## "Drop" shows while a selected unit carries siege equipment or works
## engines it can leave (not a tower's); the carry line shows what it
## carries, or (a defender near a wall) the hint that a click / tap on a
## wall stretch mans it.
func _refresh_wall_buttons() -> void:
	var drop := false
	var near_wall := false
	for u in selection:
		if sim.u_state[u] == BattleSim.U_READY and (_works_engines(u) or BattleSim.carrying(sim, u) != 0):
			drop = true
	if sim.city_on != 0 and sim.ws_x0.size() > 0:
		for u in selection:
			if sim.u_state[u] != BattleSim.U_READY:
				continue
			if BattleSim.carrying(sim, u) != 0:
				drop = true
			elif sim.u_wall[u] == 0 and sim.u_stair[u] != 1 and BattleSim.man_wall_target(sim, u).z >= 0:
				near_wall = true
	hud.set_drop_button(drop)
	_refresh_land_button()
	var note := ""
	if selected >= 0 and sim.u_state[selected] == BattleSim.U_READY:
		note = Hud.carry_note_text(sim, selected)
		if note == "" and near_wall:
			note = "Tap a wall to man it" if UiScale.is_touch() else "Click a wall to man it"
	hud.set_carry_note(note)


## (2026-11-05) The Land chip: shown while a ship of ours is selected; lit while one of them may send her landing
## party ashore (BattleSim.land_refusal), its word the men aboard, else why not.
func _refresh_land_button() -> void:
	var vis := false
	var ok := false
	var word := ""
	if sim.shp_on != 0:
		for u in selection:
			if not sim.is_ship(u) or not _mine(u):
				continue
			vis = true
			var why: String = BattleSim.land_refusal(sim, u)
			if why == "":
				ok = true
				word = "%d men" % sim.u_count0[sim.sh_party[sim.u_ship[u]]]
			elif word == "":
				word = "ashore" if sim.sh_party[sim.u_ship[u]] >= 0 and sim.sh_land[sim.u_ship[u]] >= 0 else "none"
	hud.set_land_button(vis, ok and interactive, word)


## (2026-11-05) "Land": each selected ship of ours sends her landing party ashore (ORDER_LAND, a lockstep input).
func _land() -> void:
	if not interactive or sim.shp_on == 0:
		return
	var sent := -1
	for u in selection:
		if sim.is_ship(u) and _mine(u) and BattleSim.land_refusal(sim, u) == "" and not _land_pending(u):
			_queue({"type": BattleSim.ORDER_LAND, "unit": u})
			sent = u
	_count("land")
	if sent >= 0:
		overlay.flash("The boats put off for the shore", Vector2(sim.u_cx[sent], sim.u_cy[sent]) / M * PX_PER_M)
		hud.set_land_button(true, false, "rowing")


## An ORDER_LAND for ship u is queued and not applied yet.
func _land_pending(u: int) -> bool:
	for o in sim.pending_orders:
		if int(o["type"]) == BattleSim.ORDER_LAND and int(o.get("unit", -1)) == u:
			return true
	return false


## "Drop": each selected unit carrying siege equipment puts it down where
## it stands, each working engines leaves them there (anyone's foot can
## pick them up again).
func _drop() -> void:
	var sent := 0
	var eng := 0
	for u in selection:
		if sim.u_state[u] != BattleSim.U_READY:
			continue
		if BattleSim.carrying(sim, u) != 0 or _works_engines(u):
			_queue({"type": BattleSim.ORDER_DROP, "unit": u})
			sent += 1
			if _works_engines(u):
				eng += 1
	_count("drop")
	if sent > 0 and selected >= 0:
		overlay.flash("Engines left: the men fight on foot" if eng > 0 else "Put down: free to fight",
			Vector2(sim.u_cx[selected], sim.u_cy[selected]) / M * PX_PER_M)


# ---------------------------------------------------- heroes and agents ---
# docs/DESIGN.md "Heroes and agents": the selected character's acts
# (Sabotage, Attempt for an assassin; Parley for a diplomat) are buttons in
# the HUD's order row (and keys Shift+B / T / Shift+P); a press arms the
# act, the next tap on its target gives the order (the sim walks him there:
# BattleSim.char_refusal says why not), any other tap cancels. A key whose
# act no selected character can take says why (a toast). The hidden
# assassin of the enemy is neither drawn nor picked.

const CHAR_TYPES := {"sabotage": BattleSim.ORDER_SABOTAGE, "attempt": BattleSim.ORDER_ATTEMPT,
	"parley": BattleSim.ORDER_PARLEY}


## The acts the selection's characters can arm (order type -> any).
func _char_acts() -> Dictionary:
	var out := {}
	if sim.ch_on == 0:
		return out
	for u in selection:
		if sim.u_state[u] != BattleSim.U_READY:
			continue
		if sim.u_char[u] == UT.CK_ASSASSIN:
			out[BattleSim.ORDER_SABOTAGE] = true
			if (sim.u_chf[u] & BattleSim.CHF_TRIED) == 0:
				out[BattleSim.ORDER_ATTEMPT] = true
		elif sim.u_char[u] == UT.CK_DIPLOMAT:
			out[BattleSim.ORDER_PARLEY] = true
	return out


func _refresh_char_bar() -> void:
	var acts := _char_acts()
	if not acts.has(char_armed):
		char_armed = 0
	var shown := {}
	if sim.phase != BattleSim.PHASE_DEPLOY:
		for act in CHAR_TYPES:
			if acts.has(CHAR_TYPES[act]):
				shown[act] = true
	hud.set_char_buttons(shown, str(ORDER_NAMES.get(char_armed, "")) if char_armed != 0 else "")


## A character's act button: arm (or disarm) the next tap.
func _toggle_char(typ: int) -> void:
	if not interactive:
		return
	if char_armed != typ and (sim.phase == BattleSim.PHASE_DEPLOY or not _char_acts().has(typ)):
		_char_refused(typ)
		_refresh_actions()
		return
	char_armed = typ if char_armed != typ else 0
	release_armed = false
	_count("char_arm_" + str(ORDER_NAMES.get(typ, typ)) if char_armed != 0 else "char_disarm")
	if char_armed != 0 and selected >= 0:
		var hint := {BattleSim.ORDER_SABOTAGE: "Tap an enemy battery or a shut gate",
			BattleSim.ORDER_ATTEMPT: "Tap an enemy hero or general", BattleSim.ORDER_PARLEY: "Tap a routing or wavering enemy unit"}
		overlay.flash(str(hint[char_armed]), Vector2(sim.u_cx[selected], sim.u_cy[selected]) / M * PX_PER_M)
	_refresh_actions()


## Act typ cannot be armed for the selection: a toast says why (the first
## selected unit's BattleSim.char_refusal, without a target).
func _char_refused(typ: int) -> void:
	_count("char_refused_" + str(ORDER_NAMES.get(typ, typ)))
	var why := "select a hero or an agent"
	if sim.phase == BattleSim.PHASE_DEPLOY:
		why = "not before the battle starts"
	for u in selection:
		var r: String = BattleSim.char_refusal(sim, {"type": typ, "unit": u})
		if r in ["his attempt is spent", "only an assassin", "only a diplomat", "no unit"] or r.begins_with("not yet"):
			why = r
			if sim.u_char[u] != 0:
				break
	var at := Vector2(sim.u_cx[selected], sim.u_cy[selected]) / M * PX_PER_M if selected >= 0 else camera.position
	overlay.flash("Cannot: " + why, at)


## The armed act on what is under w: every selected character of the right
## kind is given it (BattleSim.char_refusal).
func _char_tap(w: Vector2) -> void:
	var typ := char_armed
	char_armed = 0
	var o := {"type": typ}
	if typ == BattleSim.ORDER_SABOTAGE:
		var eg := _engines_at(w) if sim.n_eg > 0 else -1
		var g := _gate_at(w) if sim.city_on != 0 else -1
		var t0 := _pick_unit(w)
		if eg < 0 and t0 >= 0 and sim.u_side[t0] != player_side and sim.u_eg[t0] >= 0:
			eg = sim.u_eg[t0]  # (a tap on the battery's marker: its engines)
		if eg >= 0:
			o["eg"] = eg
			o["gate"] = -1
		elif g >= 0:
			o["eg"] = -1
			o["gate"] = g
		else:
			_count("char_cancelled")
			_refresh_actions()
			return
	else:
		var t := _pick_unit(w)
		if t < 0 or sim.u_side[t] == player_side:
			_count("char_cancelled")
			_refresh_actions()
			return
		o["target"] = t
	var sent := 0
	var why := ""
	for u in selection:
		var oc: Dictionary = o.duplicate()
		oc["unit"] = u
		var r: String = BattleSim.char_refusal(sim, oc)
		if r == "":
			_queue(oc)
			sent += 1
		elif why == "" and sim.u_char[u] != 0:
			why = r
	_count(str(ORDER_NAMES.get(typ, "char")))
	var done := {BattleSim.ORDER_SABOTAGE: "He goes to work", BattleSim.ORDER_ATTEMPT: "He goes for him",
		BattleSim.ORDER_PARLEY: "He goes with a white flag"}
	overlay.flash(str(done[typ]) if sent > 0 else ("Cannot: " + why if why != "" else "Nothing to do there"), w)
	_refresh_actions()


## Unit u is handlers whose pack is with them (dogs to release).
func _pack_ready(u: int) -> bool:
	var p: int = sim.u_pack[u]
	return p >= 0 and sim.u_state[p] == BattleSim.U_KENNEL and sim.u_kept[p] > 0


## "Release": arm (or disarm) the next tap on an enemy unit.
func _toggle_release() -> void:
	if not interactive:
		return
	var any := false
	for u in selection:
		if sim.u_state[u] == BattleSim.U_READY and _pack_ready(u):
			any = true
	release_armed = any and not release_armed
	_count("release_arm" if release_armed else "release_disarm")
	if release_armed and selected >= 0:
		overlay.flash("Tap an enemy unit to set the dogs on it",
			Vector2(sim.u_cx[selected], sim.u_cy[selected]) / M * PX_PER_M)
	_refresh_actions()


## The armed Release on enemy unit t: every selected handler unit with dogs
## in the kennel lets them loose at it (BattleSim.release_refusal).
func _release_at(t: int, w: Vector2) -> void:
	release_armed = false
	var sent := 0
	var why := ""
	for u in selection:
		if not _pack_ready(u):
			continue
		var r: String = BattleSim.release_refusal(sim, u, t)
		if r == "":
			_queue(BattleSim.make_release_order(0, u, t))
			sent += 1
		elif why == "":
			why = r
	_count("release")
	overlay.flash("The dogs are loose" if sent > 0 else ("Cannot release: " + why if why != "" else "No dogs"), w)
	_refresh_actions()


## The player's beast units running amok whose drivers can still be told
## to kill them (BattleSim.kill_refusal).
func _amok_mine() -> Array[int]:
	var out: Array[int] = []
	if sim.big_on == 0:
		return out
	for u in sim.n_units:
		if sim.u_side[u] == player_side and _mine(u) and BattleSim.kill_refusal(sim, u) == "":
			out.append(u)
	return out


## "Kill elephant" shows while a beast unit of ours runs amok.
func _refresh_kill_button() -> void:
	hud.kill_button.visible = not _amok_mine().is_empty()


## "Kill elephant": the drivers of every amok beast unit of ours kill them
## (ORDER_KILL; they die after the row's kill_delay).
func _kill_beasts() -> void:
	if not interactive:
		return
	var us := _amok_mine()
	for u in us:
		_queue({"type": BattleSim.ORDER_KILL, "unit": u})
	_count("kill_beast")
	if not us.is_empty():
		var u: int = us[0]
		overlay.flash("The drivers kill their elephants (%d s)" % (UT.stat(sim.u_type[u], "kill_delay") / 10),
			Vector2(sim.u_cx[u], sim.u_cy[u]) / M * PX_PER_M)
	hud.kill_button.visible = false


## Unit u works engines it may leave (a battery, or men who took engines
## up; not a tower's engine).
func _works_engines(u: int) -> bool:
	return sim.n_eg > 0 and sim.u_eg[u] >= 0 and UT.stat(sim.u_type[u], "fixed") == 0


## The engine group left on the field under world point w (px), or -1: the
## nearest whose middle is within its half width + 5 m.
func _engines_at(w: Vector2) -> int:
	var x := int(w.x / PX_PER_M * M)
	var y := int(w.y / PX_PER_M * M)
	var best := -1
	var bd := 0
	for g in sim.n_eg:
		if not sim.engines_free(g) or UT.stat(sim.eg_type[g], "fixed") != 0:
			continue
		var c: Vector2i = BattleSim.engines_at(sim, g)
		var r: int = maxi((int(sim.eg_ne[g]) - 1) * UT.stat(sim.eg_type[g], "file_sp") / 2 + 5 * 1024, _marker_hit_r() / 2)
		var d := (c.x - x) * (c.x - x) + (c.y - y) * (c.y - y)
		if d <= r * r and (best < 0 or d < bd):
			best = g
			bd = d
	return best


## A tap on engine group g left on the field with units selected: the
## selected unit nearest it that may work it goes and takes it up.
func _tap_engines(g: int, w: Vector2) -> void:
	var best := -1
	var bd := 0
	var why := ""
	var c: Vector2i = BattleSim.engines_at(sim, g)
	for u in selection:
		var r: String = BattleSim.engine_refusal(sim, u, g)
		if r != "":
			if why == "" or u == selected:
				why = r
			continue
		var d := FM.approx_len(sim.u_cx[u] - c.x, sim.u_cy[u] - c.y)
		if best < 0 or d < bd:
			best = u
			bd = d
	_count("engine_pickup" if best >= 0 else "engine_refused")
	if best < 0:
		overlay.flash(why, w)
		return
	_queue({"type": BattleSim.ORDER_PICKUP, "unit": best, "engines": g, "run": orders.value(best, "run")})
	overlay.flash("Taking up the engines", w)


## The piece of siege equipment on the ground under world point w (px), or
## -1: the nearest within 5 m (at least the marker hit radius / 2).
func _equip_at(w: Vector2) -> int:
	if sim.n_eq == 0:
		return -1
	var x := int(w.x / PX_PER_M * M)
	var y := int(w.y / PX_PER_M * M)
	var r := maxi(5 * 1024, _marker_hit_r() / 2)
	var best := -1
	var bd := 0
	for q in sim.n_eq:
		if sim.q_state[q] != BattleSim.Q_GROUND:
			continue
		var dx: int = sim.q_x[q] - x
		var dy: int = sim.q_y[q] - y
		var d := dx * dx + dy * dy
		if d <= r * r and (best < 0 or d < bd):
			best = q
			bd = d
	return best


## A tap on piece q with units selected: the selected unit nearest it that
## may carry it goes and picks it up (one unit a piece).
func _tap_equip(q: int, w: Vector2) -> void:
	var best := -1
	var bd := 0
	var why := ""
	for u in selection:
		var r: String = BattleSim.pickup_refusal(sim, u, q)
		if r != "":
			if why == "" or u == selected:
				why = r
			continue
		var d := FM.approx_len(sim.u_cx[u] - sim.q_x[q], sim.u_cy[u] - sim.q_y[q])
		if best < 0 or d < bd:
			best = u
			bd = d
	_count("equip_pickup" if best >= 0 else "equip_refused")
	if best < 0:
		overlay.flash(why, w)
		return
	_queue({"type": BattleSim.ORDER_PICKUP, "unit": best, "equip": q, "run": orders.value(best, "run")})
	var what := "the ram" if sim.q_kind[q] == BattleSim.EQ_RAM else "the ladders"
	if sim.q_kind[q] == BattleSim.EQ_POLES:
		what = "the scaling poles"
	elif sim.q_kind[q] == BattleSim.EQ_WAGON:
		what = "the wagon"
	elif BattleSim.EQ_SCREEN[sim.q_kind[q]] != 0:
		what = "the mantlet"
	elif BattleSim.EQ_EXPOSED[sim.q_kind[q]] != 0:
		what = "the siege tower"
	if sim.phase == BattleSim.PHASE_DEPLOY:
		overlay.flash("Assigned to %s: %s" % [what, Hud.carry_pattern_text(sim.q_kind[q],
			BattleSim.carry_files(sim, best, q))], w)
		return
	overlay.flash("Taking " + what, w)


## M: each selected unit that may goes up onto the stretch within 60 m
## nearest the enemy, at its point nearest the unit (an ordinary move order
## there: the sim takes it up the stair). (The mouse / touch way is
## _wall_click: the stretch you click.)
func _man_wall() -> void:
	var sent := 0
	var why := ""
	for u in selection:
		if sim.u_state[u] != BattleSim.U_READY or sim.u_wall[u] > 0:
			continue
		var mt := BattleSim.man_wall_target(sim, u)
		if mt.z < 0:
			continue
		var r: String = orders.wall_refusal(u, mt.x, mt.y)
		if r != "":
			why = r
			continue
		_queue(BattleSim.make_move_order(0, u, mt.x, mt.y, sim.ws_dir[mt.z],
			BattleSim.files_to_width(orders.value(u, "files"), sim.u_type[u]), orders.value(u, "run")))
		sent += 1
	_count("man_wall")
	if sent == 0 and selected >= 0:
		overlay.flash(why if why != "" else "No wall within 60 m that these men can man",
			Vector2(sim.u_cx[selected], sim.u_cy[selected]) / M * PX_PER_M)


## Shift+M: each selected unit on a wall goes down its nearer stair to
## the street at its foot (BattleSim.wall_inside), facing out, in its
## normal block.
func _come_down() -> void:
	for u in selection:
		if sim.u_state[u] != BattleSim.U_READY or sim.u_wall[u] == 0:
			continue
		var sg: int = sim.u_wall[u] - 1
		var p: Vector2i = sim.wall_inside(sg, sim.u_cx[u], sim.u_cy[u])
		var files := BattleSim.ground_files(sim.u_type[u], sim.u_alive[u])
		_queue(BattleSim.make_move_order(0, u, p.x, p.y, sim.ws_dir[sg],
			BattleSim.files_to_width(files, sim.u_type[u]), orders.value(u, "run")))
	_count("come_down")


## True if a click / tap at world point w (px) is about a wall with men to
## put on it: the point is on a stretch (BattleSim.wall_stretch_at) and a
## selected unit can man walls, already stands on one, or (an attacker
## outside) may go up by ladders or poles (BattleSim.may_ladder: it carries
## a set, or a set of its side is planted; 2026-11-01: before, such a unit
## got a plain ground move and a group's moves landed off the wall).
func _wall_click_at(w: Vector2) -> int:
	if sim.city_on == 0 or sim.ws_x0.size() == 0 or selection.is_empty():
		return -1
	var any := false
	for u in selection:
		if sim.u_state[u] == BattleSim.U_READY and (BattleSim.can_man_walls(sim, u) or sim.u_wall[u] > 0 \
				or _may_climb(u)):
			any = true
	if not any:
		return -1
	var p := w / PX_PER_M * M
	return BattleSim.wall_stretch_at(sim, int(p.x), int(p.y))


## Unit u is an attacker outside the walls that may go up by ladders or
## poles (the order rule's test: BattleSim.may_ladder, not att_inside).
func _may_climb(u: int) -> bool:
	return sim.u_wall[u] == 0 and BattleSim.may_ladder(sim, u) and not BattleSim.att_inside(sim, u)


## The planted ladders, poles or siege tower under world point w (px), or
## -1: within the marker hit radius / 2 (at least 3 m) of one of its lanes
## as drawn (from its foot 3.5 m in across the wall). Only when a selected
## unit may climb it: a tap on it is a tap on its stretch (_wall_click at
## the set's walkway point), so the second party up a planted set need not
## find the wall's own cells behind the poles and the climbing men.
func _planted_at(w: Vector2) -> int:
	if sim.n_eq == 0 or sim.city_on == 0 or selection.is_empty():
		return -1
	var any := false
	for u in selection:
		if sim.u_state[u] == BattleSim.U_READY and _may_climb(u):
			any = true
	if not any:
		return -1
	var p := w / PX_PER_M * M
	var r := float(maxi(3 * 1024, _marker_hit_r() / 2))
	var best := -1
	var bd := 0.0
	for q in sim.n_eq:
		if sim.q_state[q] != BattleSim.Q_PLANTED or sim.q_seg[q] < 0:
			continue
		if sim.q_side[q] != player_side and BattleSim.EQ_ANY[sim.q_kind[q]] == 0:
			continue
		var dir: float = sim.ws_dir[sim.q_seg[q]] * TAU / 1024.0
		var inw := -Vector2(cos(dir), sin(dir)) * 3.5 * M
		for k in maxi(BattleSim.EQ_LANES[sim.q_kind[q]], 1):
			var f: Vector2i = sim.set_ladder_foot(q, k)
			var a := Vector2(f.x, f.y)
			var d := Geometry2D.get_closest_point_to_segment(p, a, a + inw).distance_to(p)
			if d <= r and (best < 0 or d < bd):
				best = q
				bd = d
	return best


## A click / tap on wall stretch sg at world point w (px): each selected
## unit goes onto THAT stretch (a move to its point nearest the click, facing
## the stretch's way, in its own files and run; the sim takes it up a stair, or
## along the wall when it already stands on one), refused with the reason
## wall_refusal gives. The stretch flashes so a tap shows what it chose.
func _wall_click(sg: int, w: Vector2, double: bool) -> void:
	var p := w / PX_PER_M * M
	var ws := BattleSim.wall_snap(sim, int(p.x), int(p.y))
	var sent := 0
	var why := ""
	for u in selection:
		if sim.u_state[u] != BattleSim.U_READY:
			continue
		var r: String = orders.wall_refusal(u, ws.x, ws.y)
		if r != "":
			why = r
			continue
		_queue(BattleSim.make_move_order(0, u, ws.x, ws.y, sim.ws_dir[sg],
			BattleSim.files_to_width(orders.value(u, "files"), sim.u_type[u]),
			1 if double else orders.value(u, "run")))
		sent += 1
	_count("man_wall")
	overlay.flash_stretch(sg)
	if sent == 0:
		_count("wall_refused")
		overlay.flash(why if why != "" else "These men cannot go onto the wall", w)


func _withdraw() -> void:
	for u in selection:
		_queue(BattleSim.make_withdraw_order(0, u))


func _withdraw_all() -> void:
	if not interactive:
		return
	_queue(BattleSim.make_withdraw_all_order(0, player_side))


func _shift_held() -> bool:
	return _mouse_add or Input.is_key_pressed(KEY_SHIFT) or Input.is_key_pressed(KEY_CTRL)


func _open_controls() -> void:
	_count("controls_open")
	if not hud.controls.visible:
		_paused_before_controls = paused
		_set_paused(true)
	hud.controls.open()
	_gm_cancel()
	overlay.preview_on = false
	_dragging = false
	_touches.clear()
	_primary = -1
	_gesture_multi = false


func _tap(screen_pos: Vector2, double: bool, long_press := false) -> void:
	if _exit_timer > 0.0:
		_count("end_banner_skipped")
		_leave_decided()  # tap to skip the end banner
		return
	_count("double_tap" if double else ("long_press" if long_press else "tap"))
	if not interactive:
		return
	var w := _screen_to_world(screen_pos)
	if works_mode != "" and sim.phase == BattleSim.PHASE_DEPLOY:
		_works_tap(w)
		return
	if occupy_mode:
		_occupy_tap(w)
		return
	if ability_armed >= 0:
		_ability_tap(w)
		return
	if waypoint_mode and not _rmb_order:
		var hit := _wp_dot_at(w)
		if hit.x >= 0:
			var hch: Array = orders.chain(hit.x)
			if double and hit.y < hch.size() and int((hch[hit.y] as Dictionary)["attack"]) >= 0:
				return   # (the second tap of the double that added the attack: nothing to do)
			_wp_remove(hit.x, hit.y)
			return
	# A tap in a gate's doorway is about the gate: it is tested before the
	# units, so a marker floating over the gate (men on the wall above it)
	# or a unit box cannot steal it. Outside the doorway units pick first and
	# the gate's wider reach is the fallback.
	if char_armed != 0:
		_char_tap(w)
		return
	var door := _gate_doorway(w)
	if door >= 0 and _tap_gate(door, w):
		return
	var u := -1 if door >= 0 else _pick_unit(w)
	var friend_move := false
	if u >= 0 and sim.u_side[u] == player_side and not selection.is_empty():
		# A marker (loose radius) always selects; on the unit's footprint away
		# from it a plain tap is a move there (see the rules at the top).
		var wants_select := not _rmb_order and (double or add_mode or _shift_held() \
			or _marker_unit(w, _marker_hit_r()) == u)
		if not wants_select:
			friend_move = true
			u = -1
	if u >= 0 and sim.u_side[u] == player_side:
		if sim.u_state[u] != BattleSim.U_READY:
			_count("tap_on_broken_unit")
			return
		if not _mine(u):
			_not_mine_hint(u)
			return
		_count("tap_select")
		if _marker_unit(w, _tight_marker_r()) != u and _pick_unit(w, true) != u:
			_count("tap_select_loose")
		if add_mode or _shift_held():
			_toggle_in_selection(u)
		else:
			_select(u)
		return
	if u < 0 and door < 0:
		var g := _gate_at(w)
		if g >= 0 and _tap_gate(g, w):
			return
	if selection.is_empty():
		_count("tap_nothing_selected")
		return
	if u < 0:
		var q := _equip_at(w)
		if q >= 0:
			_tap_equip(q, w)
			return
		var pq := _planted_at(w) if not _wp_append() and _wall_click_at(w) < 0 else -1
		if pq >= 0:
			_count("planted_tap")
			_wall_click(sim.q_seg[pq], Vector2(sim.q_wx[pq], sim.q_wy[pq]) / M * PX_PER_M, double)
			return
		var eg := _engines_at(w) if sim.n_eg > 0 else -1
		if eg >= 0:
			_tap_engines(eg, w)
			return
	if release_armed:
		if u >= 0:
			_release_at(u, w)
			return
		release_armed = false  # (a tap elsewhere: no release)
		_count("release_cancelled")
		_refresh_actions()
		return
	if u < 0 and door < 0 and not _wp_append():
		var wsg := _wall_click_at(w)
		if wsg >= 0:
			_wall_click(wsg, w, double)
			return
	if u >= 0:
		# Enemy: attack (missile troops shoot it; double tap = charge at the run).
		var as_point := _wp_append()   # (the waypoints tool: the attack is the chain's last point, the selection and the tool stay)
		if not as_point:
			_place_clear()   # (a direct order: the ghost, if any, is stale)
		var carriers := 0
		for s in selection:
			if BattleSim.carrying(sim, s) != 0:
				carriers += 1  # carrying siege equipment: no attacking
				continue
			var ao := BattleSim.make_attack_order(0, s, u, 1 if double else orders.value(s, "run"))
			if double:
				ao["charge"] = 1   # (a double tap charges home: a caracole row does not ride a pass at it)
			if as_point:
				ao["append"] = 1
			_queue(ao)
		if as_point:
			_count("wp_attack")
			overlay.flash("Attack added as the last stop", w)
		if carriers > 0:
			overlay.flash("Carrying siege equipment: put it down first (Drop) to fight", w)
		return
	if _ground_tap_hook(w, double):
		return
	var dest := w / PX_PER_M * M
	if friend_move:
		overlay.flash("Move", w)
	var app := _wp_append()
	if app and double:
		# The second tap of a double: the stop the first tap added runs.
		for su in selection:
			_wp_last_run(su)
		return
	if selection.size() == 1:
		# Ground: move there keeping frontage, facing the direction of travel
		# (a waypoint: from the end of its chain).
		var ce: Vector3i = orders.chain_end(selected) if app else Vector3i(orders.value(selected, "ax"),
			orders.value(selected, "ay"), orders.value(selected, "face"))
		var dx := dest.x - ce.x
		var dy := dest.y - ce.y
		var face: int = ce.z
		if dx * dx + dy * dy > 4.0 * M * M:
			face = int(round(atan2(dy, dx) * 1024.0 / TAU)) & 1023
		var width: int = BattleSim.files_to_width(orders.value(selected, "files"), sim.u_type[selected])
		var why: String = orders.wall_refusal(selected, int(dest.x), int(dest.y))
		if why != "":
			_count("wall_refused")
			overlay.flash(why, w)
			return
		var mo := BattleSim.make_move_order(0, selected, int(dest.x), int(dest.y), face, width,
			1 if double else orders.value(selected, "run"))
		if app:
			_wp_queue_append(mo, w)
		else:
			_queue(mo)
		return
	_group_move(dest, double)


## Radius (sim units) of a unit marker's hit circle at the current zoom:
## generous on touch screens. Also the least reach of a gate's doorway.
func _marker_hit_r() -> int:
	var mr := maxf(Overlay.MARKER_MIN_R, Overlay.MARKER_SCREEN_R / camera.zoom.x)
	var hit_k := 2.3 if UiScale.is_touch() else 1.7
	return int(mr * hit_k / PX_PER_M * M)


## Gate whose doorway is under world point w (px), or -1: the opening's own
## rectangle in its frame (half width + 1 m along the wall, the wall's
## thickness + 1.5 m each side across it), widened to at least the marker
## hit radius so it stays a fair touch target when zoomed out. The nearest
## gate wins if two overlap.
func _gate_doorway(w: Vector2) -> int:
	if sim.n_gates == 0:
		return -1
	var x := int(w.x / PX_PER_M * M)
	var y := int(w.y / PX_PER_M * M)
	var touch_r := _marker_hit_r()
	var ry := maxi(sim.wall_t / 2 + 1536, touch_r)
	var best := -1
	var best_d := 0
	for g in sim.n_gates:
		var rx := maxi((sim.g_hw[g] + 1) * int(M), touch_r)
		var f: Vector2i = sim.gate_frame(g, x, y)
		if absi(f.x) <= rx and absi(f.y) <= ry:
			var d := f.x * f.x + f.y * f.y
			if best < 0 or d < best_d:
				best = g
				best_d = d
	return best


## Gate within reach of world point w (px), or -1: wider than the doorway,
## used only when no unit was picked.
func _gate_at(w: Vector2) -> int:
	if sim.n_gates == 0:
		return -1
	var x := w.x / PX_PER_M * M
	var y := w.y / PX_PER_M * M
	var reach_y: int = sim.wall_t / 2 + 4 * 1024
	for g in sim.n_gates:
		var reach_x := int((sim.g_hw[g] + 3) * M)
		var f: Vector2i = sim.gate_frame(g, int(x), int(y))
		if absi(f.x) <= reach_x and absi(f.y) <= reach_y:
			return g
	return -1


## A tap on gate g (w the tap, world px). Defenders: open or close it,
## whatever is selected (the selection stays, nothing moves). Attackers:
## batteries shoot it, foot go to its face and hack at it (cavalry and
## missile troops cannot); an open or broken gate is a move. Returns true if
## the tap was used.
func _tap_gate(g: int, w: Vector2) -> bool:
	var st: int = sim.g_state[g]
	if sim.city_def == player_side:
		if st == BattleSim.GATE_BROKEN:
			overlay.flash("The gate is broken: it cannot be shut", w)
			return true
		var any := -1
		for u in sim.n_units:
			if sim.u_side[u] == player_side and sim.u_state[u] == BattleSim.U_READY and _mine(u):
				any = u
				break
		if any < 0:
			return true
		var close := 1 if st == BattleSim.GATE_OPEN else 0
		if close == 1 and sim.gate_busy(g):
			overlay.flash("Men in the gateway: it cannot be shut now", w)
			return true
		_count("gate_close" if close == 1 else "gate_open")
		_queue({"type": BattleSim.ORDER_GATE, "unit": any, "gate": g, "on": close})
		overlay.flash("Closing the gate" if close == 1 else "Opening the gate", w)
		return true
	if selection.is_empty() or st != BattleSim.GATE_CLOSED:
		return false  # an open or broken gate: a tap there is a move
	var sent := 0
	var refused := 0
	var ram := false
	var iron := not BattleSim.gate_hackable(sim, g)
	var ladders := false
	var fire := false
	var beast := false
	for u in selection:
		var c := UT.cls(sim.u_type[u])
		var k := BattleSim.carrying(sim, u)
		var inside: bool = sim.u_lq[u] >= 0 and (sim.u_wall[u] > 0 \
			or sim.reach_at(sim.u_ax[u], sim.u_ay[u]) == sim.reach_at(sim.g_ix[g], sim.g_iy[g]))
		var ok := false
		if k == BattleSim.EQ_RAM:
			ok = true
			ram = true
		elif k != 0 and BattleSim.EQ_LANES[k] > 0:
			ladders = true
		elif c == UT.CLS_ART or (inside and c != UT.CLS_CAV):
			ok = true
		elif (c == UT.CLS_INF or c == UT.CLS_PIKE) and not iron:
			ok = true
		elif not iron and k == 0 and UT.stat(sim.u_type[u], "gate_walls") >= sim.city_walls:
			ok = true  # elephants batter the gates of low walls
			beast = true
		elif c == UT.CLS_MISSILE and k == 0 and sim.u_wall[u] == 0 and UT.ammo_stat(sim.spec_kind(u), "fire") > 0:
			ok = true  # fire missiles: shoot the gate alight from where they stand
			fire = true
		if ok:
			_queue({"type": BattleSim.ORDER_ATTACK, "unit": u, "target": -1, "gate": g,
				"run": orders.value(u, "run")})
			sent += 1
		else:
			refused += 1
	_count("gate_attack")
	if ram:
		overlay.flash("RAM THE GATE: the ram goes at it and batters it", w)
	elif fire and sent > 0:
		overlay.flash("Shoot the gate: fire missiles set it alight (Ammo: fire)", w)
	elif beast and sent > 0:
		overlay.flash("The elephants batter the gate", w)
	elif sent == 0 and ladders:
		overlay.flash("Carrying ladders or a siege tower: tap a stretch of wall to plant it", w)
	elif sent == 0 and iron:
		overlay.flash("Swords cannot break this iron-bound gate: a ram or artillery breaks it", w)
	elif sent == 0:
		overlay.flash("Cavalry cannot break a gate (elephants only at walls 0-1); missile troops only with fire missiles", w)
	elif refused > 0:
		overlay.flash("Foot hack at the gate, engines shoot it; the others stay", w)
	return true


## Move the whole selection to `dest` (sim units), keeping the units'
## positions relative to each other, rotated so the group faces the way it
## travels (relative to the primary unit's facing).
func _group_move(dest: Vector2, double: bool) -> void:
	_count("group_move")
	# (A waypoint: the group's shape and facing where its chains end.)
	var app := _wp_append()
	var at := {}
	for u in selection:
		at[u] = orders.chain_end(u) if app else Vector3i(orders.value(u, "ax"), orders.value(u, "ay"), orders.value(u, "face"))
	var cx := 0.0
	var cy := 0.0
	for u in selection:
		cx += (at[u] as Vector3i).x
		cy += (at[u] as Vector3i).y
	cx /= selection.size()
	cy /= selection.size()
	var d := dest - Vector2(cx, cy)
	var ref: int = (at[selected] as Vector3i).z if at.has(selected) else orders.value(selected, "face")
	var turn := 0
	if d.length_squared() > 4.0 * M * M:
		var want := int(round(atan2(d.y, d.x) * 1024.0 / TAU)) & 1023
		turn = ((want - ref + 512) & 1023) - 512
	var rot := turn * TAU / 1024.0
	for u in selection:
		var e: Vector3i = at[u]
		var rel := Vector2(e.x - cx, e.y - cy).rotated(rot)
		var p := dest + rel
		var face: int = (e.z + turn) & 1023
		var width: int = BattleSim.files_to_width(orders.value(u, "files"), sim.u_type[u])
		var why: String = orders.wall_refusal(u, int(p.x), int(p.y))
		if why != "":
			_count("wall_refused")
			overlay.flash(why, p / M * PX_PER_M)
			continue
		var mo := BattleSim.make_move_order(0, u, int(p.x), int(p.y), face, width,
			1 if double else orders.value(u, "run"))
		if app:
			_wp_queue_append(mo, p / M * PX_PER_M)
		else:
			_queue(mo)


func _finish_line(double_run: bool) -> void:
	if selection.is_empty() or not overlay.preview_ok:
		_count("line_too_short")
		return
	if _confirm_on():
		_place_from_line()
		return
	_count("line_drag" if selection.size() == 1 else "line_drag_group")
	for p in overlay.preview_group():
		var u: int = p["unit"]
		var c: Vector2 = p["centre"] / PX_PER_M * M
		var why: String = orders.wall_refusal(u, int(c.x), int(c.y))
		if why != "":
			_count("wall_refused")
			overlay.flash(why, p["centre"])
			continue
		var mo := BattleSim.make_move_order(0, u, int(c.x), int(c.y), p["facing"], p["width"],
			1 if double_run else orders.value(u, "run"))
		if _wp_append():
			_wp_queue_append(mo, p["centre"])
		else:
			_queue(mo)


## The matchup mark: with a unit selected, the enemy unit at screen point
## sp gets a triangle beside its marker (a HUD mark only; no sim state).
func _update_matchup(sp: Vector2) -> void:
	var u := -1
	if selected >= 0 and not selection.is_empty() and not hud.is_over_ui(sp):
		var t := _pick_unit(_screen_to_world(sp))
		if t >= 0 and sim.u_side[t] != player_side and sim.u_state[t] < BattleSim.U_DESTROYED:
			u = t
	if u != overlay.match_u or (u >= 0 and overlay.match_v != Traits.matchup(sim.u_otype[selected], sim.u_otype[u])):
		overlay.match_u = u
		overlay.match_v = Traits.matchup(sim.u_otype[selected], sim.u_otype[u]) if u >= 0 else 0
		overlay.queue_redraw()


## Radius (sim units) of the tight marker hit circle (the marker itself).
func _tight_marker_r() -> int:
	return int(maxf(Overlay.MARKER_MIN_R, Overlay.MARKER_SCREEN_R / camera.zoom.x) * TIGHT_PICK_K / PX_PER_M * M)


## The unit whose marker centre is nearest world point w (px) within marker
## radius r (sim units), or -1. Any side; hidden and destroyed units skip.
func _marker_unit(w: Vector2, r: int) -> int:
	var x := int(w.x / PX_PER_M * M)
	var y := int(w.y / PX_PER_M * M)
	var mr := maxf(Overlay.MARKER_MIN_R, Overlay.MARKER_SCREEN_R / camera.zoom.x)
	var lift := int(2.2 * mr / PX_PER_M * M)
	var best := -1
	var best_d := 0
	if BoardView.oblique:
		# The oblique view: the markers stand upright over the units; measure on the board.
		var bw := BoardView.to_board(w)
		var rb := float(r) / M * PX_PER_M
		var best_f := 0.0
		for u in sim.n_units:
			if sim.u_state[u] >= BattleSim.U_DESTROYED or sim.hidden_from(u, player_side):
				continue
			var bc := marker_board(u, mr)
			var dd := bw.distance_squared_to(bc)
			if dd <= rb * rb and (best < 0 or dd < best_f):
				best = u
				best_f = dd
		return best
	for u in sim.n_units:
		if sim.u_state[u] >= BattleSim.U_DESTROYED or sim.hidden_from(u, player_side):
			continue
		var mdx: int = x - sim.u_cx[u]
		var mdy: int = y - (sim.u_cy[u] - lift)
		var md := mdx * mdx + mdy * mdy
		if md <= r * r and (best < 0 or md < best_d):
			best = u
			best_d = md
	return best


## tight: only the marker's own circle and the unit's footprint count (used
## to select our units while a selection exists, so taps between units
## reach the ground).
func _pick_unit(w: Vector2, tight := false) -> int:
	var x := int(w.x / PX_PER_M * M)
	var y := int(w.y / PX_PER_M * M)
	var margin := 0 if tight else int(2.5 * M)
	var best := -1
	var best_d := 0
	# The symbol marker above each unit is a hit target first (generous on
	# touch screens); a tap on a marker wins over a unit's ground box under
	# it, since markers float over neighbouring units when zoomed out.
	best = _marker_unit(w, _tight_marker_r() if tight else _marker_hit_r())
	if best >= 0:
		return best
	for u in sim.n_units:
		if sim.u_state[u] >= BattleSim.U_DESTROYED or sim.hidden_from(u, player_side):
			continue
		var in_box: bool = x >= sim.u_minx[u] - margin and x <= sim.u_maxx[u] + margin \
			and y >= sim.u_miny[u] - margin and y <= sim.u_maxy[u] + margin
		if not in_box:
			continue
		var dx: int = x - sim.u_cx[u]
		var dy: int = y - sim.u_cy[u]
		var d := dx * dx + dy * dy
		if best < 0 or d < best_d:
			best = u
			best_d = d
	return best


# ------------------------------------------------------------ the 3D view ---

## The 3D view (BoardView.v3d): the Node3D scene under the overlay and the HUD; the 2D world layers stay built (the overlay, the
## orders and the 3D layers read them) but are not drawn.
func _v3d_build(board: Node2D) -> void:
	for n in [board, terrain, city, works, ships, trays, soldiers, trees]:
		if n != null:
			(n as CanvasItem).visible = false
	if "--v3d-show-2d" in OS.get_cmdline_user_args():
		for n in [terrain, city]:
			(n as CanvasItem).visible = true
	view3d = View3D.new()
	add_child(view3d)
	view3d.setup(self, sim, PX_PER_M)
	# The battle opens facing the player's side: an army deployed in the north half turns the table half round.
	var cy := 0.0
	var nn := 0
	for u in sim.n_units:
		if (sim.u_side[u] & 1) == (player_side & 1) and sim.u_state[u] < BattleSim.U_DESTROYED:
			cy += float(sim.u_cy[u])
			nn += 1
	var y0 := PI if nn > 0 and cy / nn < sim.field_h * 0.5 and not sim.is_ai_side(player_side) else 0.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--v3d-yaw="):
			y0 = deg_to_rad(float(a.get_slice("=", 1)))
	var e0 := BoardView.ELEVATION_DEG
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--v3d-tilt="):
			e0 = clampf(float(a.get_slice("=", 1)), V3D_TILT_MIN, V3D_TILT_MAX)
	BoardView.set_view(y0, e0)


const V3D_TILT_MIN := 25.0
const V3D_TILT_MAX := 60.0
const V3D_KEY_TURN := 1.4        # radians a second (Q / E held)
const V3D_KEY_TILT := 30.0       # degrees a second (Home / End held)
const V3D_INERTIA_SEC := 0.35    # the turn's inertia decays with this time constant
const V3D_TWIST_DEAD := 0.14     # radians (8 degrees) of two-finger twist before it turns the table


## Turn the 3D camera by dyaw (radians) and tilt it by dtilt (degrees) about the ground point under screen point `pivot` (it stays
## under the same screen point).
func _v3d_turn(dyaw: float, dtilt: float, pivot: Vector2) -> void:
	if view3d == null:
		return
	camera.force_update_scroll()
	var g := _screen_to_world(pivot)
	BoardView.set_view(wrapf(BoardView.yaw + dyaw, -PI, PI), clampf(BoardView.elev_deg + dtilt, V3D_TILT_MIN, V3D_TILT_MAX))
	camera.force_update_scroll()
	var s := get_canvas_transform() * BoardView.to_board(g)
	camera.position += (s - pivot) / camera.zoom
	_clamp_camera()
	overlay.queue_redraw()


## Held keys and the inertia of a turn (every frame, 3D only).
func _v3d_process(delta: float) -> void:
	_v3d_twist_step()
	var c := get_viewport_rect().size * 0.5
	var turn := 0.0
	if not _gm and not hud.book.visible and not hud.controls.visible:
		if Controls.held("group_rotate_left"):
			turn += V3D_KEY_TURN * delta
		if Controls.held("group_rotate_right"):
			turn -= V3D_KEY_TURN * delta
		var tilt := 0.0
		if Controls.held("camera_tilt_up"):
			tilt += V3D_KEY_TILT * delta
		if Controls.held("camera_tilt_down"):
			tilt -= V3D_KEY_TILT * delta
		if turn != 0.0 or tilt != 0.0:
			_v3d_yaw_vel = 0.0
			_v3d_turn(turn, tilt, c)
			return
	if not _v3d_turning and absf(_v3d_yaw_vel) > 0.02:
		_v3d_turn(_v3d_yaw_vel * delta, 0.0, c)
		_v3d_yaw_vel *= exp(-delta / V3D_INERTIA_SEC)
	elif not _v3d_turning:
		_v3d_yaw_vel = 0.0


## A turning step of a gesture: turn now and keep its rate for the inertia.
func _v3d_drag_turn(dyaw: float, dtilt: float, pivot: Vector2) -> void:
	_v3d_turning = true
	var dt := maxf(get_process_delta_time(), 1.0 / 240.0)
	_v3d_yaw_vel = lerpf(_v3d_yaw_vel, dyaw / dt, 0.5)
	_v3d_turn(dyaw, dtilt, pivot)


# ---------------------------------------------------------------- input ---

func _screen_to_world(p: Vector2) -> Vector2:
	return BoardView.to_world(get_canvas_transform().affine_inverse() * p)


## Screen (viewport) point -> board point (px): the camera's own space (the world in the top view).
func _screen_to_board(p: Vector2) -> Vector2:
	return get_canvas_transform().affine_inverse() * p


## Board point (px) of unit u's marker centre (marker radius mr, world px).
func marker_board(u: int, mr: float) -> Vector2:
	return BoardView.to_board(Vector2(sim.u_cx[u], sim.u_cy[u]) / M * PX_PER_M) - Vector2(0, Overlay.marker_dy(mr) + TrayLayer.wall_lift(sim, u))


## Screen (viewport) point of unit u's marker centre (tests).
func marker_screen(u: int) -> Vector2:
	return get_canvas_transform() * marker_board(u, maxf(Overlay.MARKER_MIN_R, Overlay.MARKER_SCREEN_R / camera.zoom.x))


## World point (px) -> screen (viewport) point, through the board transform (tests, hints).
func world_to_screen(w: Vector2) -> Vector2:
	return get_canvas_transform() * BoardView.to_board(w)


## Centre the camera on world point w (px).
func _cam_to(w: Vector2) -> void:
	camera.position = BoardView.to_board(w)


func _input(event: InputEvent) -> void:
	if dive_t >= 0.0 and ((event is InputEventKey and event.pressed and not event.echo) \
			or (event is InputEventMouseButton and event.pressed) or (event is InputEventScreenTouch and event.pressed)):
		dive_finish()   # a tap or a key skips the dive (and is not an order)
		get_viewport().set_input_as_handled()
		return
	# Modifiers come from the mouse event itself (key state can be missed by
	# the browser). The emulated touch of a click is handled at release, after
	# this has run.
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			_mouse_add = mb.shift_pressed or mb.ctrl_pressed or mb.meta_pressed
			_mouse_alt = mb.alt_pressed or Input.is_key_pressed(KEY_G)
		if _gm and mb.pressed:
			# While moving a group: wheel turns it, right click cancels.
			if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
				_gm_turn(-GM_STEP)
				get_viewport().set_input_as_handled()
			elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_gm_turn(GM_STEP)
				get_viewport().set_input_as_handled()
			elif mb.button_index == MOUSE_BUTTON_RIGHT:
				_count("group_move_cancelled")
				_gm_cancel()
				get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if hud.book.visible or hud.controls.visible or (menu != null and menu.visible):
		return  # the book, the controls page and the Menu are modal; they handle their own keys
	if event is InputEventScreenTouch:
		_update_matchup(event.position if event.pressed else Vector2(-1e6, -1e6))
		_on_touch(event)
		if not event.pressed and overlay.hover_w.x >= 0.0:
			overlay.hover_w = Vector2(-1, -1)   # a lifted finger hovers nothing
			overlay.queue_redraw()
	elif event is InputEventScreenDrag:
		_update_matchup(event.position)
		_on_drag(event)
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_count("wheel")
			_zoom_at(mb.position, 1.15)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_zoom_at(mb.position, 1.0 / 1.15)
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			if mb.device == InputEvent.DEVICE_ID_EMULATION:
				return
			if mb.pressed:
				_last_touch = false
				_rmb = true
				_rmb_shift = mb.shift_pressed
				_rmb_pos = mb.position
				_rmb_drag = false
				_rmb_pan = false
				_rmb_turn = false
			elif _rmb:
				_right_release(mb.position)
		elif mb.button_index == MOUSE_BUTTON_MIDDLE:
			_mouse_pan = mb.pressed
			if mb.pressed:
				_count("mouse_pan")
		# Left button arrives again as an emulated touch; ignore it here.
	elif event is InputEventMouseMotion:
		_update_matchup((event as InputEventMouseMotion).position)
		if _rmb:
			_right_motion(event as InputEventMouseMotion)
		elif _mouse_pan:
			camera.position -= (event as InputEventMouseMotion).relative / camera.zoom
			_clamp_camera()
		elif occupy_mode:
			# Occupy armed: the lit building under the mouse shows its fans.
			var ow := _screen_to_world((event as InputEventMouseMotion).position)
			_occupy_focus(_occupy_building_at(ow), "Click to send them in")
		elif sim.city_on != 0 and not selection.is_empty() and not UiScale.is_touch():
			# Walls: the stretch under the mouse lights up (overlay); not in
			# a gate's doorway, where a click is about the gate. Touch has no
			# hover: its emulated motion would leave the route preview (and
			# this) drawn to wherever the last tap fell.
			var hw := _screen_to_world((event as InputEventMouseMotion).position)
			overlay.hover_w = hw if _gate_doorway(hw) < 0 else Vector2(-1, -1)
			overlay.queue_redraw()
	elif event is InputEventMagnifyGesture:
		var mg := event as InputEventMagnifyGesture
		_zoom_at(mg.position, mg.factor)
	elif event is InputEventPanGesture:
		camera.position += (event as InputEventPanGesture).delta * 8.0 / camera.zoom
		_clamp_camera()
	elif event is InputEventKey and event.pressed and not event.echo:
		_on_key(event as InputEventKey)


## Right button moved: past the drag threshold it either lays out a line
## (units selected) or pans (nothing selected).
func _right_motion(e: InputEventMouseMotion) -> void:
	if not _rmb_drag and not _rmb_pan:
		if e.position.distance_to(_rmb_pos) <= DRAG_THRESHOLD:
			return
		if view3d != null and (selection.is_empty() or Input.is_key_pressed(KEY_ALT) or not interactive):
			_rmb_pan = true
			_rmb_turn = true
			_count("v3d_drag_turn")
		elif interactive and not selection.is_empty() and _exit_timer <= 0.0:
			_rmb_drag = true
			overlay.preview_on = true
			_cancel_left_drag()
			_count("right_drag_line")
		else:
			_rmb_pan = true
			_count("mouse_pan")
	if _rmb_drag:
		_line_preview(_rmb_pos, e.position)
	elif _rmb_turn:
		# (3D: like the spike's orbit: across turns the table, up and down tilts it)
		_v3d_drag_turn(-e.relative.x * deg_to_rad(0.3), e.relative.y * 0.2,
			get_viewport_rect().size * 0.5)
	elif _rmb_pan:
		camera.position -= e.relative / camera.zoom
		_clamp_camera()


func _cancel_left_drag() -> void:
	if _box:
		_box_end(false)


func _right_release(pos: Vector2) -> void:
	_rmb = false
	if _rmb_drag:
		_rmb_drag = false
		overlay.preview_on = false
		_finish_line(false)
		_rmb_shift = false
		return
	if _rmb_pan:
		_rmb_pan = false
		_rmb_turn = false
		_v3d_turning = false
		_rmb_shift = false
		return
	var now := Time.get_ticks_msec() / 1000.0
	var double := now - _last_rtap_time < DOUBLE_TAP_SEC and pos.distance_to(_last_rtap_pos) < DOUBLE_TAP_DIST
	if double:
		_last_rtap_time = -10.0
	else:
		_last_rtap_time = now
		_last_rtap_pos = pos
	if selection.is_empty() and _exit_timer <= 0.0:
		_rmb_shift = false
		return
	_count("right_click")
	_rmb_order = true
	_tap(pos, double)
	_rmb_order = false
	_rmb_shift = false


## Left click with a real mouse: select the unit under it (shift / ctrl adds
## or removes), empty ground deselects. Targeting modes, the end banner, the
## deployment works and the gates / engines / equipment keep the tap rules.
func _left_click(pos: Vector2, double: bool, long_press: bool) -> void:
	var w := _screen_to_world(pos)
	var armed := char_armed != 0 or release_armed or ability_armed >= 0 or (works_mode != "" and sim.phase == BattleSim.PHASE_DEPLOY)
	if _exit_timer > 0.0 or not interactive or armed or _gate_doorway(w) >= 0:
		_tap(pos, double, long_press)
		return
	if _shift_held() or waypoint_mode:
		var hit := _wp_dot_at(w)
		if hit.x >= 0:
			_wp_remove(hit.x, hit.y)
			return
	var u := _pick_unit(w)
	if u >= 0:
		if sim.u_side[u] != player_side:
			_count("click_enemy")
			return
		if sim.u_state[u] != BattleSim.U_READY:
			_count("tap_on_broken_unit")
			return
		if not _mine(u):
			_not_mine_hint(u)
			return
		_count("tap_select")
		if _shift_held() or add_mode:
			_toggle_in_selection(u)
		else:
			_select(u)
		return
	if _wall_click_at(w) >= 0 and not _shift_held() and not add_mode:
		_tap(pos, double, long_press)  # a click on a wall mans it
		return
	if not selection.is_empty() and (_gate_at(w) >= 0 or _equip_at(w) >= 0 or _planted_at(w) >= 0 \
			or (sim.n_eg > 0 and _engines_at(w) >= 0)):
		_tap(pos, double, long_press)
		return
	_count("click_ground")
	if not (_shift_held() or add_mode):
		_select(-1)


## The digit 1..9 of a key press (0 when it is not one; the physical key when the layout moved the digit).
func _digit_of(e: InputEventKey) -> int:
	for code in [e.keycode, e.physical_keycode]:
		if code >= KEY_1 and code <= KEY_9:
			return code - KEY_0
	return 0


## Keyboard shortcuts, from the controls table (game/controls.gd).
func _on_key(e: InputEventKey) -> void:
	var dg := _digit_of(e)
	if dg > 0 and not e.alt_pressed and not e.meta_pressed:
		_count("key_group")
		if e.ctrl_pressed:
			_group_assign(dg, "set")
		elif e.shift_pressed:
			_group_assign(dg, "add")
		else:
			_group_select(dg)
		return
	var act := Controls.action_for_key(e, "battle")
	if act != "":
		_count("key_" + act)
	match act:
		"pause":
			_toggle_pause()
		"speed_up":
			_step_speed(1)
		"speed_down":
			_step_speed(-1)
		"select_all":
			_select_group("all")
		"select_line":
			_select_group("line")
		"select_skirmish":
			_select_group("skirmish")
		"select_shock":
			_select_group("shock")
		"select_horse":
			_select_group("horse")
		"select_guns":
			_select_group("guns")
		"undo":
			_undo()
		"deselect":
			if occupy_mode:
				_occupy_cancel(true)
			elif ability_armed >= 0:
				_ability_cancel(true)
			elif _gm or _gm_pending:
				_count("group_move_cancelled")
				_gm_cancel()
			elif place_on:
				_count("place_cancel")
				_place_clear()
			else:
				_select(-1)
		"run":
			_toggle_run()
		"halt":
			_halt()
		"fire":
			_toggle_fire()
		"skirmish":
			_toggle_skirmish()
		"stance":
			_cycle_stance()
		"bounds":
			_toggle_bounds()
		"occupy":
			_toggle_occupy()
		"deploy":
			_toggle_deploy()
		"refill":
			_toggle_refill()
		"ammo":
			_toggle_ammo()
		"forage":
			_toggle_forage()
		"man_wall":
			_man_wall()
		"come_down":
			_come_down()
		"drop":
			_drop()
		"land":
			_land()
		"release":
			_toggle_release()
		"sabotage", "attempt", "parley":
			_toggle_char(int(CHAR_TYPES[act]))
		"orders_overlay":
			hud.orders_button.button_pressed = not hud.orders_button.button_pressed
		"ready":
			if place_on:
				_place_go()
			else:
				_deploy_ready()
		"group_rotate_left":
			_gm_turn(-GM_STEP)
		"group_rotate_right":
			_gm_turn(GM_STEP)
		"readout":
			hud.set_stats_expanded(not hud.stats_expanded)
		"book":
			_open_book(sim.u_otype[selected] if selected >= 0 else -1, "book_open_key")
		"controls":
			_open_controls()
		"zoom_in":
			_zoom_at(get_viewport_rect().size * 0.5, 1.25)
		"zoom_out":
			_zoom_at(get_viewport_rect().size * 0.5, 0.8)
		"fullscreen":
			if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			else:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)


## Held keys: W A S D / arrows pan.
func _keys_held(delta: float) -> void:
	if hud.book.visible or hud.controls.visible:
		return
	var v := Vector2.ZERO
	if Controls.held("pan_left"):
		v.x -= 1
	if Controls.held("pan_right"):
		v.x += 1
	if Controls.held("pan_up"):
		v.y -= 1
	if Controls.held("pan_down"):
		v.y += 1
	if v != Vector2.ZERO:
		camera.position += v * PAN_SPEED * delta / camera.zoom
		_clamp_camera()
	# Long press on a unit on the field: its unit book page (any selection).
	if _primary >= 0 and not _dragging and not _gesture_multi and _field_lp_start > 0.0 \
			and Time.get_ticks_msec() / 1000.0 - _field_lp_start >= hud.LONG_PRESS_SEC:
		_field_lp_start = -1.0
		var u := _pick_unit(_screen_to_world(_press_pos))
		if u >= 0:
			_open_book(sim.u_otype[u], "book_open_longpress")


func _on_touch(e: InputEventScreenTouch) -> void:
	var is_mouse := e.device == InputEvent.DEVICE_ID_EMULATION
	if e.pressed:
		_last_touch = not is_mouse
		if hud.is_over_ui(e.position):
			# A finger over the HUD never starts a one-finger action, but a
			# second finger landing there (a thumb on the chip rows) while one
			# is on the field still joins the pinch / pan.
			if is_mouse or _touches.is_empty() or _touches.has(e.index):
				_count("touch_on_ui")
				return
			_count("touch_on_ui_joins_gesture")
		if not is_mouse:
			_mouse_add = false
			_mouse_alt = false
		_touches[e.index] = e.position
		if not is_mouse:
			var tnow := Time.get_ticks_msec()
			if _touches.size() == 1:
				_tt_t0 = tnow
				_tt_ok = false
				_tt_start.clear()
			elif _touches.size() == 2:
				_tt_ok = tnow - _tt_t0 <= TWO_TAP_DOWN_MS
			else:
				_tt_ok = false
			_tt_start[e.index] = e.position
		if _touches.size() == 1:
			_primary = e.index
			_press_pos = e.position
			_dragging = false
			_gesture_multi = false
			_field_lp_start = Time.get_ticks_msec() / 1000.0 if not is_mouse else -1.0
			_press_sec = Time.get_ticks_msec() / 1000.0
			_stray_press = not is_mouse and Time.get_ticks_msec() - _multi_end_ms < STRAY_TAP_MS
			_place_drag = _place_press(e.position)   # (on a handle of the ghost)
			if _place_drag >= 0:
				_field_lp_start = -1.0
		elif _touches.size() >= 2:
			_place_drag = -1
			overlay.place_hot = -1
			# Second finger: cancel any one-finger action, start pinch/pan.
			if not _gesture_multi:
				_count("pinch")
				if _dragging and overlay.preview_on:
					_count("line_cancelled_by_second_finger")
				elif not _dragging:
					_count("tap_cancelled_by_second_finger")
			_gesture_multi = true
			_dragging = false
			overlay.preview_on = false
			_box_end(false)
			if _touches.size() == 3 and not _gm and interactive and not selection.is_empty():
				_gm_arm()
			elif _touches.size() >= 4 and (_gm or _gm_pending):
				_count("group_move_cancelled")
				_gm_cancel()
			_start_pinch()
		return
	if not _touches.has(e.index):
		return
	_touches.erase(e.index)
	if _tt_ok and _touches.is_empty():
		_tt_ok = false
		if Time.get_ticks_msec() - _tt_t0 <= TWO_TAP_TOTAL_MS and interactive:
			_gm_pending = false
			_gesture_multi = false
			_primary = -1
			_count("deselect_two_finger")
			_gm_cancel()
			_waypoints_off()
			_select(-1)
			if coop_hud != null:
				coop_hud.flash("Deselected", 1.5)
			return
	if _gm and not _gm_mouse:
		# Lifting a finger places the group.
		_gm_commit()
	_gm_pending = false
	if _gesture_multi:
		if _touches.size() >= 2:
			_start_pinch()
		else:
			_v3d_turning = false   # (3D: a twist let go keeps turning a little: the inertia)
		if _touches.is_empty():
			_gesture_multi = false
			_primary = -1
			_multi_end_ms = Time.get_ticks_msec()
		return
	if e.index != _primary:
		return
	_primary = -1
	var now := Time.get_ticks_msec() / 1000.0
	var double := now - _last_tap_time < DOUBLE_TAP_SEC and e.position.distance_to(_last_tap_pos) < DOUBLE_TAP_DIST
	if _place_drag >= 0:
		_place_release(double, now, e.position)
		return
	if _dragging:
		_dragging = false
		if _works_drag:
			_works_drag = false
			overlay.works_drag = false
			_works_line(overlay.preview_a, overlay.preview_b)
			return
		if _gm and _gm_mouse:
			_gm_commit()
			return
		if _box:
			_box_end(true)
			return
		if not overlay.preview_on:
			_count("pan_drag")
		if overlay.preview_on:
			overlay.preview_on = false
			_finish_line(false)
		return
	if _field_lp_start < 0.0 and not is_mouse:
		return  # the long press opened the unit book
	_field_lp_start = -1.0
	if _stray_press:
		_stray_press = false
		_count("tap_after_gesture_dropped")
		return   # a finger that landed just after a pinch or a pan: not a tap
	if is_mouse:
		_left_click(e.position, double, now - _press_sec >= SELECT_LONG_PRESS_SEC)
	else:
		_tap(e.position, double, false)
	if double:
		_last_tap_time = -10.0
	else:
		_last_tap_time = now
		_last_tap_pos = e.position


func _on_drag(e: InputEventScreenDrag) -> void:
	if not _touches.has(e.index):
		return
	_touches[e.index] = e.position
	if _tt_ok and _tt_start.has(e.index) and e.position.distance_to(_tt_start[e.index]) > TWO_TAP_MOVE:
		_tt_ok = false
	if _gesture_multi:
		if _gm_pending or _gm:
			_gm_touch_update()
			if _gm:
				return
		_update_pinch()
		return
	if e.index != _primary:
		return
	if _place_drag >= 0:
		_place_drag_to(e.position)
		return
	var is_mouse := e.device == InputEvent.DEVICE_ID_EMULATION
	if not _dragging and e.position.distance_to(_press_pos) > DRAG_THRESHOLD:
		_dragging = true
		_field_lp_start = -1.0
		if works_mode == "stakes" and sim.phase == BattleSim.PHASE_DEPLOY and interactive:
			# Lay a stakes line along the drag.
			_works_drag = true
			overlay.works_drag = true
			overlay.preview_a = _screen_to_world(_press_pos)
			overlay.preview_b = overlay.preview_a
		elif is_mouse and _mouse_alt and interactive and not selection.is_empty():
			# Alt (or G) + drag: move the selection as it stands.
			_gm_begin()
			_gm_mouse = true
			_gm_mouse_start = _press_pos
			_count("alt_drag_move")
		elif is_mouse and interactive and not _rmb:
			# Mouse left drag: box select (Shift adds).
			_box = true
			overlay.box_on = true
			overlay.box_a = _screen_to_world(_press_pos)
			_count("box_select")
		elif not selection.is_empty() and interactive:
			overlay.preview_on = true
	if not _dragging:
		return
	if _works_drag:
		overlay.preview_b = _screen_to_world(e.position)
		overlay.queue_redraw()
	elif _gm and _gm_mouse:
		_gm_move = BoardView.dir_world((e.position - _gm_mouse_start) / camera.zoom.x)
		_gm_update()
	elif _box:
		overlay.box_b = _screen_to_world(e.position)
	elif overlay.preview_on:
		_line_preview(_press_pos, e.position)
	else:
		# No unit selected: one-finger drag pans.
		camera.position -= e.relative / camera.zoom
		_clamp_camera()


## The drag-to-line preview from screen point a to b (touch drag, right drag).
func _line_preview(a: Vector2, b: Vector2) -> void:
	overlay.preview_a = _screen_to_world(a)
	overlay.preview_b = _screen_to_world(b)
	# One rank is the longest line (the order rule clamps the frontage the
	# same way): the line stops growing there.
	var lmax: float = overlay.max_line_px()
	var dv: Vector2 = overlay.preview_b - overlay.preview_a
	overlay.preview_clamped = lmax > 0.0 and dv.length() > lmax
	if overlay.preview_clamped:
		overlay.preview_b = overlay.preview_a + dv.normalized() * lmax
	overlay.preview_ok = overlay.preview_a.distance_to(overlay.preview_b) >= MIN_LINE_M * PX_PER_M
	overlay.queue_redraw()


# ------------------------------------------------------------ box select ---

func _box_end(apply: bool) -> void:
	if not _box:
		return
	_box = false
	overlay.box_on = false
	if not apply:
		return
	var rect := Rect2(overlay.box_a, overlay.box_b - overlay.box_a).abs()
	if BoardView.oblique:
		# (The box as dragged on the screen: on the board.)
		var ba := BoardView.to_board(overlay.box_a)
		rect = Rect2(ba, BoardView.to_board(overlay.box_b) - ba).abs()
	if not _mouse_add:
		_select(-1)
	var any := false
	for u in sim.n_units:
		if sim.u_side[u] != player_side or sim.u_state[u] != BattleSim.U_READY or not _mine(u):
			continue
		var c := Vector2(sim.u_cx[u], sim.u_cy[u]) / M * PX_PER_M
		var mk := c - Vector2(0, 2.2 * maxf(Overlay.MARKER_MIN_R, Overlay.MARKER_SCREEN_R / camera.zoom.x))
		if BoardView.oblique:
			mk = marker_board(u, maxf(Overlay.MARKER_MIN_R, Overlay.MARKER_SCREEN_R / camera.zoom.x))
			c = BoardView.to_board(c)
		if (rect.has_point(c) or rect.has_point(mk)) and not selection.has(u):
			if not any and selection.is_empty():
				_select(u)
			else:
				_toggle_in_selection(u)
			any = true


# ----------------------------------------------------------- group move ---

## Three fingers are down with units selected: remember where, and wait for
## a clear movement or twist before showing the ghost (so a pinch that
## briefly gains a third finger issues nothing).
func _gm_arm() -> void:
	_gm_pending = true
	var keys := _touches.keys()
	keys.sort()
	_gm_start_keys = keys.slice(0, 3)
	_gm_start_mid = _three_mid()
	_gm_start_ang = []
	for k in _gm_start_keys:
		_gm_start_ang.append(((_touches[k] as Vector2) - _gm_start_mid).angle())


func _three_mid() -> Vector2:
	var m := Vector2.ZERO
	for k in _gm_start_keys:
		m += _touches[k]
	return m / 3.0


func _gm_touch_update() -> void:
	for k in _gm_start_keys:
		if not _touches.has(k):
			return
	var mid := _three_mid()
	var rot := 0.0
	for i in 3:
		var a := ((_touches[_gm_start_keys[i]] as Vector2) - mid).angle()
		rot += wrapf(a - float(_gm_start_ang[i]), -PI, PI)
	rot /= 3.0
	var move := mid - _gm_start_mid
	if _gm_pending and (move.length() > GM_MOVE_PX or absf(rot) > GM_TURN_RAD):
		_gm_pending = false
		_gm_begin()
		_count("three_finger_move")
	if _gm:
		_gm_move = BoardView.dir_world(move / camera.zoom.x)
		_gm_rot = rot
		_gm_update()


func _gm_begin() -> void:
	_gm_units.clear()
	_gm_base.clear()
	var c := Vector2.ZERO
	for u in selection:
		if sim.u_state[u] != BattleSim.U_READY:
			continue
		_gm_units.append(u)
		var b := {"ax": orders.value(u, "ax"), "ay": orders.value(u, "ay"), "face": orders.value(u, "face"),
			"files": orders.value(u, "files")}
		_gm_base.append(b)
		c += Vector2(int(b["ax"]), int(b["ay"]))
	if _gm_units.is_empty():
		return
	_gm_centre = c / _gm_units.size()
	_gm_move = Vector2.ZERO
	_gm_rot = 0.0
	_gm = true
	_gm_mouse = false
	overlay.preview_on = false
	_gm_update()


func _gm_turn(step: float) -> void:
	if not _gm:
		return
	_gm_rot += step
	_count("group_rotate")
	_gm_update()


## Destination of each unit: its anchor rotated about the group centre and
## moved; facing turned by the same angle; frontage kept.
func _gm_dest() -> Array:
	var out: Array = []
	var turn := int(round(_gm_rot * 1024.0 / TAU))
	var mv := _gm_move / PX_PER_M * M
	for i in _gm_units.size():
		var b: Dictionary = _gm_base[i]
		var rel := Vector2(int(b["ax"]), int(b["ay"])) - _gm_centre
		var p := _gm_centre + rel.rotated(_gm_rot) + mv
		out.append({"unit": _gm_units[i], "x": int(p.x), "y": int(p.y),
			"face": (int(b["face"]) + turn) & 1023, "files": int(b["files"])})
	return out


func _gm_update() -> void:
	var gh: Array = []
	for d in _gm_dest():
		gh.append({"unit": d["unit"], "front": Vector2(d["x"], d["y"]) / M * PX_PER_M,
			"face": d["face"], "files": d["files"]})
	overlay.ghosts = gh
	var deg := int(round(rad_to_deg(_gm_rot)))
	overlay.ghost_hint = "turn %+d deg" % deg if deg != 0 else ""
	overlay.queue_redraw()


func _gm_commit() -> void:
	if not _gm:
		return
	if _gm_move.length() * camera.zoom.x < 6.0 and absf(_gm_rot) < 0.03:
		_gm_cancel()
		return
	if absf(_gm_rot) >= 0.03:
		_count("group_rotate_placed")
	for d in _gm_dest():
		var u: int = d["unit"]
		if sim.u_state[u] != BattleSim.U_READY:
			continue
		var width: int = BattleSim.files_to_width(int(d["files"]), sim.u_type[u])
		_queue(BattleSim.make_move_order(0, u, int(d["x"]), int(d["y"]), int(d["face"]), width,
			orders.value(u, "run")))
	_gm_cancel()


func _gm_cancel() -> void:
	_gm = false
	_gm_pending = false
	_gm_mouse = false
	overlay.ghosts = []
	overlay.ghost_hint = ""
	overlay.queue_redraw()


func _two_touches() -> Array:
	var keys := _touches.keys()
	keys.sort()
	return [_touches[keys[0]], _touches[keys[1]]]


func _start_pinch() -> void:
	if _touches.size() < 2:
		return
	var t := _two_touches()
	_pinch_dist = (t[0] as Vector2).distance_to(t[1])
	_pinch_mid = ((t[0] as Vector2) + (t[1] as Vector2)) * 0.5
	_pinch_ang = ((t[1] as Vector2) - (t[0] as Vector2)).angle()
	_v3d_acc_ang = 0.0
	_v3d_twist = false
	_v3d_twist_prev = 1e9
	_v3d_yaw_vel = 0.0
	_v3d_c3 = Vector2(-1e9, -1e9)


func _update_pinch() -> void:
	if _touches.size() < 2:
		return
	var t := _two_touches()
	var dist := (t[0] as Vector2).distance_to(t[1])
	var mid := ((t[0] as Vector2) + (t[1] as Vector2)) * 0.5
	if view3d != null and _touches.size() >= 3 and not _gm and not _gm_pending and selection.is_empty():
		_v3d_three()
		return
	if view3d != null and _touches.size() == 2 and _v3d_pinch(t, dist, mid):
		return
	camera.position -= (mid - _pinch_mid) / camera.zoom
	if _pinch_dist > 1.0 and dist > 1.0:
		_zoom_at(mid, dist / _pinch_dist)
	_pinch_dist = dist
	_pinch_mid = mid
	_clamp_camera()


## The 3D view's two-finger gesture, beside the pan and the pinch (which go on as in the other views): the twist turns the table
## about the fingers' midpoint once it passes V3D_TWIST_DEAD (so a pinch or a pan does not turn it). Three fingers with nothing
## selected (`_v3d_three`): across turns, up and down tilts. Returns true when the step is used up here (never, for two fingers).
func _v3d_pinch(_pair: Array, _dist: float, _mid: Vector2) -> bool:
	return false


## The twist, once a frame from both fingers' latest places (the touch events come a finger at a time: a parallel pan would
## swing the line between them back and forth within a frame), turning about their midpoint past the dead zone.
func _v3d_twist_step() -> void:
	if not _gesture_multi or _touches.size() != 2 or _gm or _gm_pending:
		_v3d_twist_prev = 1e9
		return
	var t := _two_touches()
	var ang := ((t[1] as Vector2) - (t[0] as Vector2)).angle()
	if _v3d_twist_prev > 1e8:
		_v3d_twist_prev = ang
		return
	var da := wrapf(ang - _v3d_twist_prev, -PI, PI)
	_v3d_twist_prev = ang
	if not _v3d_twist:
		_v3d_acc_ang += da
		if absf(_v3d_acc_ang) <= V3D_TWIST_DEAD:
			return
		_v3d_twist = true
		_count("v3d_twist")
		da = _v3d_acc_ang   # (the dead zone's turn is not lost)
	if da != 0.0:
		_v3d_drag_turn(da, 0.0, ((t[0] as Vector2) + (t[1] as Vector2)) * 0.5)


## Three fingers with nothing selected in the 3D view (no group move to make): their centroid's motion across turns the table,
## up and down tilts it (down: more from above), about the screen's centre.
func _v3d_three() -> void:
	var c := Vector2.ZERO
	for k in _touches:
		c += _touches[k]
	c /= float(_touches.size())
	if _v3d_c3.x > -1e8:
		var d := c - _v3d_c3
		_v3d_drag_turn(-d.x * deg_to_rad(0.3), d.y * 0.25, get_viewport_rect().size * 0.5)
	_v3d_c3 = c


func _zoom_at(screen_pos: Vector2, factor: float) -> void:
	# The canvas transform lags camera.position until the camera's next scroll
	# update: refresh it first, or a pan made just before (the two-finger
	# midpoint in _update_pinch) is read as zoom drift and undone.
	camera.force_update_scroll()
	var before := _screen_to_board(screen_pos)
	var z := clampf(camera.zoom.x * factor, ZOOM_MIN, ZOOM_MAX)
	camera.zoom = Vector2(z, z)
	camera.force_update_scroll()
	var after := _screen_to_board(screen_pos)
	camera.position += before - after
	_clamp_camera()


func _clamp_camera() -> void:
	var bf := BoardView.board_field()
	camera.position = camera.position.clamp(bf.position, bf.end)


# -------------------------------------------------------------- co-op ---

func _coop_ready() -> void:
	coop.auto_update = false
	coop_hud = CoopHud.new()
	coop_hud.region_name = coop_region
	add_child(coop_hud)
	coop_hud.build(coop, hud)
	coop_hud.leave_pressed.connect(func():
		_end_scenario("coop_lobby_leave")
		exit_requested.emit())
	hud.gift_pressed.connect(_gift)
	orders.source = _coop_pending
	coop.changed.connect(func():
		_prune_selection()
		overlay.queue_redraw())
	coop.resolved.connect(func():
		coop_hud.flash("The result is in on the server. Back to campaign when you like.", 8.0))
	coop.note.connect(func(text: String, _kind: String): coop_hud.flash(text, 4.0))


## The session stepped the sim (lockstep frames due by wall time).
func _coop_step(delta: float) -> void:
	if coop.ls != null and coop.ls.sim != sim:
		_rebind(coop.ls.sim)
	if coop.ls != null and not has_meta("coop_select_done"):
		# Testing aid: --coop-select=U[,U] once the battle runs here.
		set_meta("coop_select_done", true)
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--coop-select="):
				var want: Array = []
				if a.get_slice("=", 1) == "mine":
					for u in sim.n_units:
						if coop.can_order(u) and want.size() < 2:
							want.append(u)
				else:
					want = Array(a.get_slice("=", 1).split(","))
				for part in want:
					if coop.can_order(int(part)):
						if selection.is_empty():
							_select(int(part))
						else:
							_toggle_in_selection(int(part))
	var t0 := Time.get_ticks_usec()
	var steps: int = coop.update(delta)
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	_coop_test_aids()
	var ls = coop.ls
	if ls == null:
		soldiers.set_alpha(1.0)
		return
	if ls.sim != sim:
		_rebind(ls.sim)
	if steps > 0:
		_after_tick(ms / steps)
		soldiers.upload()
		_view_tick()
	var p: bool = ls.paused != 0
	if p != paused:
		paused = p
		hud.pause_button.text = "Play" if paused else "Pause"
	var q: int = ls.speed_q
	speed_q = q
	if Vector2i(q, ls.vote_speed_q if ls.vote_speed_by == coop.me else q) != _shown_speed:
		_update_speed_text()
	# Interpolation between the last two ticks.
	var a := 1.0
	if not paused:
		var f: float = clampf(coop.wall_acc / TICK_SEC, 0.0, 1.0)
		a = f if q >= 4 else clampf((ls.acc + f * q) / 4.0, 0.0, 1.0)
	soldiers.set_alpha(a)


## Testing aids (tests/live_shots.py): --coop-start-alone (the host starts
## without waiting), --coop-test-withdraw-at=F (withdraw the army at frame
## F), --coop-auto-exit (back to the campaign once the battle is over).
func _coop_test_aids() -> void:
	for a in OS.get_cmdline_user_args():
		if a == "--coop-start-alone" and coop.phase == "lobby" and coop.is_host() and coop.room.is_open():
			coop.start_battle()
		elif a.begins_with("--coop-test-withdraw-at=") and coop.ls != null and not has_meta("test_withdrawn") \
				and coop.ls.frame >= int(a.get_slice("=", 1)) and coop.can_issue():
			set_meta("test_withdrawn", true)
			_withdraw_all()
		elif a == "--coop-auto-exit" and coop.final_frame >= 0 and not has_meta("test_exit") \
				and coop.ls.frame >= coop.final_frame + 10:
			set_meta("test_exit", true)
			_end_scenario("coop_auto_exit")
			exit_requested.emit()


## The session restored a snapshot (or started): every view part follows
## the new sim.
func _rebind(s) -> void:
	sim = s
	soldiers.sim = s
	overlay.sim = s
	orders.sim = s
	terrain.sim = s
	city.sim = s
	trees.sim = s
	works.sim = s
	hud._sim = s
	if view3d != null:
		view3d.sim = s   # (the 3D view reads the sim the lockstep session runs: a joiner's restored copy)
	soldiers.upload()
	_view_tick()
	_prune_selection()


func _mine(u: int) -> bool:
	return coop == null or coop.can_order(u)


func _not_mine_hint(u: int) -> void:
	_count("tap_ally_unit")
	if coop != null and coop.ls != null and coop_hud != null:
		var c: int = coop.ls.commander(u)
		coop_hud.flash("%s commands this unit." % (coop.player_name(c) if c >= 0 else "Nobody"), 2.0)


## Orders not applied yet, for the preview: the lockstep queue (both
## players), the sim's own, and what this player queued this frame.
func _coop_pending() -> Array:
	if coop.ls == null:
		return []
	var out: Array = coop.ls.pending_sim_orders()
	for o in coop.outbox:
		var t := int(o.get("type", 0))
		if (t >= BattleSim.ORDER_MOVE and t <= BattleSim.ORDER_REFILL or t == BattleSim.ORDER_PLACE \
				or t == BattleSim.ORDER_AMMO or t == BattleSim.ORDER_FORAGE or t == BattleSim.ORDER_STANCE) and t != BattleSim.ORDER_WITHDRAW_ALL:
			var d: Dictionary = o.duplicate()
			d["tick"] = sim.tick
			out.append(d)
	return out


func _coop_cards() -> void:
	if coop.ls == null:
		return
	# A colour band on every card of this side once another player takes
	# part on it (whose unit is whose).
	var band: bool = not coop.teammates_in(coop.me).is_empty()
	for u in sim.n_units:
		if sim.u_side[u] != player_side:
			continue
		var c: int = coop.ls.commander(u)
		hud.set_card_owner(u, c != coop.me, coop.player_color(c) if c >= 0 else Color(0.5, 0.5, 0.5), band)
	if not selection.is_empty():
		_prune_selection()


## Co-op speed vote for q (a lockstep input; it applies at its frame when
## agreed). Choosing this player's own open proposal again would withdraw
## it, so that sends nothing; choosing the speed in force withdraws it.
func _coop_request_speed(q: int) -> void:
	var ls = coop.ls
	if ls == null:
		return
	var mine: bool = ls.vote_speed_by == coop.me
	if mine and q == ls.vote_speed_q:
		return
	if q == ls.speed_q:
		if mine:
			coop.request_speed(ls.vote_speed_q)
		return
	coop.request_speed(q)


## The team-mates the selection can be gifted to: the other players taking
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
	_count("gift")
	_t("coop_gift", {"units": selection.size(), "to": to, "tick": sim.tick})
	coop.gift(selection, to)
	coop_hud.flash("%d unit%s given to %s." % [selection.size(), "" if selection.size() == 1 else "s", coop.player_name(to)], 2.5)
	_select(-1)


## Another player takes part and is connected (leaving hands them our units).
func _coop_others_in() -> bool:
	if coop == null or coop.ls == null:
		return false
	for p in coop.ls.active_players():
		if p != coop.me and coop.connected(p):
			return true
	return false


## Who takes our units when we leave a live co-op battle: a connected player
## of our side (lockstep's keeper rule: the lowest), else the battle AI.
func _coop_heir_name() -> String:
	var side: int = coop.ls.side_of(coop.me)
	for p in coop.ls.side_players(side):
		if p != coop.me and coop.connected(p):
			return coop.player_name(p)
	return "the battle AI"


## Leaving a live co-op battle: what to upload from this device, if
## anything ({res, decided}; {}: nothing - another player carries on or
## the host uploads). Leaves the room either way.
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


# ----------------------------------------------------------- field works ---
# Deployment: the palette arms a mode; a tap in our zone places a stakes
# line / a caltrop field facing the enemy, a drag lays a stakes line along
# it, a tap on a placed stakes line turns it an eighth (Rotate mode, or
# again in Stakes mode), Remove takes a piece back. Orders go through
# _queue (ORDER_WORKS, the lockstep in a live battle); the sim's
# works_rule keeps them to the zone.

func _on_works_mode(mode: String) -> void:
	works_mode = "" if works_mode == mode else mode
	_count("works_" + (mode if works_mode != "" else "off"))
	if works_mode != "":
		_select(-1)
	_refresh_works_palette()


func _refresh_works_palette() -> void:
	if hud == null:
		return
	var on: bool = sim.phase == BattleSim.PHASE_DEPLOY and sim.fw_on != 0 and interactive
	var ks := Vector2i.ZERO
	var kc := Vector2i.ZERO
	if on:
		ks = sim.works_count(player_side, BattleSim.EQ_STAKES)
		kc = sim.works_count(player_side, BattleSim.EQ_CALTROPS)
		on = ks.x + ks.y + kc.x + kc.y > 0
	if not on:
		works_mode = ""
	hud.set_works(on, ks, kc, works_mode)


## Our placed stakes / caltrops piece at world point w (-1 none).
func _own_work_at(w: Vector2) -> int:
	var x := int(w.x / PX_PER_M * M)
	var y := int(w.y / PX_PER_M * M)
	for q in sim.n_eq:
		var k: int = sim.q_kind[q]
		if sim.q_side[q] == player_side and sim.q_state[q] == BattleSim.Q_FIXED and BattleSim.EQ_FW[k] != 0 \
				and BattleSim.EQ_H[k] == 0 and sim.fw_inside(q, x, y):
			return q
	return -1


func _enemy_face() -> int:
	return 768 if player_side == 0 else 256


func _works_tap(w: Vector2) -> void:
	var q := _own_work_at(w)
	var x := int(w.x / PX_PER_M * M)
	var y := int(w.y / PX_PER_M * M)
	if works_mode == "remove":
		if q < 0:
			overlay.flash("Tap a stakes line or caltrop field of yours to take it back", w)
			return
		_queue({"type": BattleSim.ORDER_WORKS, "equip": q, "on": 0})
		_count("works_remove")
	elif works_mode == "rotate" or (works_mode == "stakes" and q >= 0 and BattleSim.EQ_HIDE[sim.q_kind[q]] == 0):
		if q < 0:
			overlay.flash("Tap a stakes line of yours to turn it", w)
			return
		_queue({"type": BattleSim.ORDER_WORKS, "equip": q, "x": sim.q_x[q], "y": sim.q_y[q],
			"facing": (sim.q_face[q] + 128) & 1023})
		_count("works_rotate")
	else:
		var k := BattleSim.EQ_STAKES if works_mode == "stakes" else BattleSim.EQ_CALTROPS
		if sim.works_count(player_side, k).x <= 0:
			overlay.flash("None left to place: tap one to turn it or use Remove", w)
			return
		if BattleSim.deploy_clamp(sim, player_side, x, y).z == 0:
			overlay.flash("Place field works in your zone", w)
			return
		_queue({"type": BattleSim.ORDER_WORKS, "kind": k, "x": x, "y": y, "facing": _enemy_face()})
		_count("works_place")
	_refresh_works_palette()


## A drag from a to b (world px) in Stakes mode: a stakes line on the
## drag's middle, along it, its front toward the enemy.
func _works_line(a: Vector2, b: Vector2) -> void:
	var d := b - a
	if d.length() < MIN_LINE_M * PX_PER_M:
		_works_tap(a)
		return
	var n := Vector2(-d.y, d.x)
	if (n.y > 0.0) == (player_side == 0):
		n = -n  # (the side toward the enemy)
	var face := int(round(atan2(n.y, n.x) * 1024.0 / TAU)) & 1023
	var c := (a + b) * 0.5 / PX_PER_M * M
	if sim.works_count(player_side, BattleSim.EQ_STAKES).x <= 0:
		overlay.flash("No stakes lines left to place", b)
		return
	_queue({"type": BattleSim.ORDER_WORKS, "kind": BattleSim.EQ_STAKES, "x": int(c.x), "y": int(c.y), "facing": face})
	_count("works_line")
	_refresh_works_palette()


# ---------------------------------------------------------------- sounds ---
# View only (docs/STATUS.md 8b): after each tick, compare the sim's counters
# and unit / gate states with the last tick and play one clip per event
# bucket (AudioFx caps them per 100 ms), placed by the distance and side of
# the camera centre. Nothing here writes the sim.

var _au_on := false
var _au_started := false
var _au_prev := {}            # counter name -> last value
var _au_state := PackedInt32Array()
var _au_stair := PackedInt32Array()
var _au_ghp := PackedInt32Array()
var _au_gst := PackedInt32Array()
var _au_t0 := PackedInt32Array()      # artillery landing tracking (as game/overlay.gd does)
var _au_stamp := PackedInt32Array()
var _au_walk := 0
var _au_live: Array[int] = []
var _au_rec := {}
const AU_MELEE_MIN := 3


func _au_delta(key: String, v: int) -> int:
	var d := v - int(_au_prev.get(key, v))
	_au_prev[key] = v
	return d


## Volume and pan of a sim point as heard from the camera centre.
func _au_mix(sx: int, sy: int) -> Vector2:
	var p := BoardView.to_board(Vector2(sx, sy) / M * PX_PER_M)
	var half := get_viewport_rect().size / camera.zoom * 0.5
	var d := (p - camera.position) / half
	return Vector2(clampf(1.15 - d.length() * 0.55, 0.0, 1.0), clampf(d.x, -1.0, 1.0))


## The unit nearest the camera centre meeting a test (see the match), -1 none.
func _au_nearest(kind: int) -> int:
	var best := -1
	var bd := 1.0e30
	var tick: int = sim.tick
	for u in sim.n_units:
		if sim.u_alive[u] <= 0 or sim.u_state[u] >= BattleSim.U_DESTROYED:
			continue
		var ok := false
		match kind:
			0: ok = sim.u_fighting[u] > 0
			1: ok = tick - sim.u_charged_t[u] <= 1
			2: ok = sim.u_ftarget[u] >= 0 and sim.u_neng[u] == 0
			3: ok = sim.u_neng[u] > 0 and sim.u_ftarget[u] >= 0
			4: ok = sim.u_amok[u] != 0
			5: ok = sim.u_hand[u] >= 0
			6: ok = sim.u_burn[u] > 0
			7: ok = sim.t_m_gun[sim.u_type[u]] != 0 and sim.u_neng[u] == 0 and sim.u_fire_acc[u] <= 2
			8: ok = sim.u_neng[u] > 0 and sim.t_m_gun[sim.u_type[u]] != 0 and sim.u_ftarget[u] >= 0
		if not ok:
			continue
		var cw := BoardView.to_world(camera.position) / PX_PER_M * M
		var d := Vector2(sim.u_cx[u] - cw.x, sim.u_cy[u] - cw.y).length_squared()
		if d < bd:
			bd = d
			best = u
	return best


func _au_at_unit(kind: int, clip: String, bucket: String, gain: float = 1.0) -> void:
	var u := _au_nearest(kind)
	if u < 0:
		return
	var m := _au_mix(sim.u_cx[u], sim.u_cy[u])
	AudioFx.play(clip, m.x * gain, m.y, bucket)


func _audio_tick() -> void:
	if not _au_started:
		if sim.phase == BattleSim.PHASE_DEPLOY:
			return
		_au_started = true
		AudioFx.play("horn_start", 0.9, 0.0, "horn")
		_au_prev["att"] = sim.stat_attacks
		_au_prev["imp"] = sim.stat_impacts
		_au_prev["shots"] = sim.stat_shots
		_au_prev["gvol"] = sim.stat_volleys
		_au_prev["gcan"] = sim.stat_cannon
		_au_prev["bolts"] = sim.stat_bolts
		_au_prev["stones"] = sim.stat_stones
		_au_prev["crush"] = sim.stat_crush
		_au_prev["amok"] = sim.stat_amok
		_au_prev["rel"] = sim.stat_released
		_au_prev["tup"] = sim.stat_tower_hits
		_au_prev["tdown"] = sim.stat_towers_down
		_au_prev["destr"] = sim.stat_breaches + sim.stat_collapses
		_au_state = sim.u_state.duplicate()
		_au_stair = sim.u_stair.duplicate()
		_au_ghp = sim.g_hp.duplicate()
		_au_gst = sim.g_state.duplicate()
		return
	# melee, charge impacts, volleys
	if _au_delta("att", sim.stat_attacks) >= AU_MELEE_MIN:
		_au_at_unit(0, "melee", "melee", 0.8)
	if _au_delta("imp", sim.stat_impacts) > 0:
		_au_at_unit(1, "charge", "impact")
	var crush := _au_delta("crush", sim.stat_crush)
	if _au_delta("amok", sim.stat_amok) > 0:
		_au_at_unit(4, "elephant", "beast", 0.9)
	elif crush > 0:
		_au_at_unit(1, "elephant", "beast", 0.9)
	var gv := _au_delta("gvol", sim.stat_volleys)
	if gv > 0:
		_au_at_unit(7, "musket", "volley", 0.9)  # (a gun volley's shots: no bow sound with it)
	if _au_delta("shots", sim.stat_shots) > 0 and gv == 0:
		var u := _au_nearest(2)
		if u >= 0:
			var m := _au_mix(sim.u_cx[u], sim.u_cy[u])
			var far: bool = UT.stat(sim.u_type[u], "m_range") >= 90 * 1024
			AudioFx.play("volley" if far else "whoosh", m.x * 0.8, m.y, "volley")
	var nb := _au_delta("bolts", sim.stat_bolts)
	var ns := _au_delta("stones", sim.stat_stones)
	var nc := _au_delta("gcan", sim.stat_cannon)
	if nc > 0:
		_au_at_unit(8, "cannon", "art")
		nb -= nc  # (a gun's roundshot is a bolt to the sim)
	if nb > 0:
		_au_at_unit(3, "bolt_release", "art")
	if ns > 0:
		_au_at_unit(3, "stone_release", "art")
	if _au_delta("rel", sim.stat_released) > 0:
		_au_at_unit(5, "dogs", "beast")
	if _au_delta("tup", sim.stat_tower_hits) > 0:
		AudioFx.play("bolt_impact", 0.5, 0.0, "ladder")
	if _au_delta("tdown", sim.stat_towers_down) > 0:
		AudioFx.play("gate_break", 0.6, 0.0, "ladder")
	if _au_delta("destr", sim.stat_breaches + sim.stat_collapses) > 0:
		AudioFx.play("gate_break", 0.8, 0.0, "ladder")  # (a wall stretch breached, a building fallen)
	if sim.stat_bolts + sim.stat_stones > 0:
		_au_landings()
	_au_units()
	if sim.n_gates > 0:
		_au_gates()
	if sim.tick % 5 == 0:
		var f := 0.0
		var u := _au_nearest(6)
		if u >= 0:
			f = _au_mix(sim.u_cx[u], sim.u_cy[u]).x
		AudioFx.fire_level(f)


## Units breaking / rallying and climbs starting: the loudest event of the tick.
func _au_units() -> void:
	var nu: int = sim.n_units
	if _au_state.size() != nu:
		_au_state = sim.u_state.duplicate()
		_au_stair = sim.u_stair.duplicate()
		return
	var best := 0.0
	var clip := ""
	var pan := 0.0
	var bucket := ""
	for u in nu:
		var st: int = sim.u_state[u]
		var old: int = _au_state[u]
		var sg: int = sim.u_stair[u]
		var og: int = _au_stair[u]
		_au_state[u] = st
		_au_stair[u] = sg
		var c := ""
		var b := "state"
		if st != old:
			if st == BattleSim.U_ROUTING and old == BattleSim.U_READY and sim.u_amok[u] == 0:
				c = "unit_break"
			elif st == BattleSim.U_READY and old == BattleSim.U_ROUTING:
				c = "unit_rally"
		elif sg != og and sg >= 2 and og < 2:
			c = "creak"
			b = "ladder"
		if c == "":
			continue
		var m := _au_mix(sim.u_cx[u], sim.u_cy[u])
		if m.x > best:
			best = m.x
			clip = c
			pan = m.y
			bucket = b
	if clip != "":
		AudioFx.play(clip, best, pan, bucket)


func _au_gates() -> void:
	var ng: int = sim.n_gates
	if _au_ghp.size() != ng:
		_au_ghp = sim.g_hp.duplicate()
		_au_gst = sim.g_state.duplicate()
		return
	var best := 0.0
	var clip := ""
	var pan := 0.0
	for g in ng:
		var hp: int = sim.g_hp[g]
		var st: int = sim.g_state[g]
		var c := ""
		if st == BattleSim.GATE_BROKEN and _au_gst[g] != BattleSim.GATE_BROKEN:
			c = "gate_break"
		elif hp < _au_ghp[g]:
			c = "gate_blow"
		_au_ghp[g] = hp
		_au_gst[g] = st
		if c == "":
			continue
		var m := _au_mix(sim.g_x[g], sim.g_y[g])
		if m.x > best or (c == "gate_break" and clip == "gate_blow"):
			best = m.x
			clip = c
			pan = m.y
	if clip != "":
		AudioFx.play(clip, best, pan, "gate")


## Artillery landings: the walk of game/overlay.gd's _track_missiles, kept
## for bolts, stones and bursts only (arrows land silently).
func _au_landings() -> void:
	var cap: int = sim.pr_t1.size()
	if _au_t0.size() != cap:
		_au_t0.resize(cap)
		_au_t0.fill(-1)
		_au_stamp.resize(cap)
		_au_stamp.fill(0)
		_au_live.clear()
		_au_rec.clear()
	_au_walk += 1
	var buckets: PackedInt32Array = sim.pr_bucket
	var nxt: PackedInt32Array = sim.pr_next
	for b in buckets.size():
		var p := buckets[b]
		while p >= 0:
			_au_stamp[p] = _au_walk
			if _au_t0[p] != sim.pr_t0[p]:
				if _au_rec.has(p):
					_au_live.erase(p)
					_au_land(p)
				_au_t0[p] = sim.pr_t0[p]
				var mk: int = UT.stat(sim.pr_ty[p], "m_kind")
				if mk > 0:
					var ak: int = sim.pr_ak[p]
					var blast: int = UT.stat(sim.pr_ty[p], "m_blast") + (UT.ammo_stat(ak, "blast") if ak >= 0 else 0)
					_au_rec[p] = [sim.pr_x[p], sim.pr_y[p], mk, blast, sim.pr_t0[p]]
					_au_live.append(p)
			p = nxt[p]
	var k := 0
	while k < _au_live.size():
		var p := _au_live[k]
		if _au_stamp[p] == _au_walk and _au_t0[p] == _au_rec[p][4]:
			k += 1
			continue
		_au_land(p)
		_au_live.remove_at(k)


func _au_land(p: int) -> void:
	var r: Array = _au_rec[p]
	_au_rec.erase(p)
	var m := _au_mix(r[0], r[1])
	AudioFx.play("burst" if r[3] > 0 else ("bolt_impact" if r[2] == 1 else "stone_impact"), m.x, m.y, "art")


# ----------------------------------------- confirm orders and the placement tool ---
# View only (docs/design/ui.md "Confirm orders and the placement tool"). The owner's phone report: with units selected any
# single tap on the board was a move order, so a stray tap behind an engaged line turned it round. With Confirm orders on
# (game/confirm_orders.gd: auto = while the last input was a touch) a tap on the ground, a line drag or a double tap places a
# GHOST of the selection (the order preview's footprints and dots, the facing arrow) with three kinds of upright handles:
# body (move), front (turn, 15 degree steps, soft stops on the facing it had and on facing the nearest enemy), ends (width,
# one rank at most). The toolbar (HUD): Go sends the order once (a move for each unit, as the tap or the line drag would have)
# and clears the selection; Run; Waypoint (the ghost becomes the next stop and the tool stays open); X. The ghost is a few
# fields here and in the overlay: no sim state, no lockstep input until Go. The gesture guards (always): a tap within
# STRAY_TAP_MS of a pinch or a two-finger pan ending is dropped; with Confirm off a tap that orders a fighting unit must be
# held HOLD_ORDER_SEC.

const ConfirmOrders := preload("res://game/confirm_orders.gd")
const STRAY_TAP_MS := 300          # a finger down this soon after a pinch / two-finger pan ended is a stray tap
const HOLD_ORDER_SEC := 0.25       # Confirm off: a tap that orders a unit in the fight must be held this long
const PLACE_SNAP_DEG := 15.0       # the front handle turns in steps of this
const PLACE_DETENT_DEG := 5.0      # ... with a soft stop this close to the old facing and to facing the enemy

var _last_touch: bool = UiScale.is_touch()   # the last input on the field was a finger (Confirm orders: auto)
var _multi_end_ms := -100000       # when the last pinch / two-finger pan ended
var _stray_press := false          # the finger now down came soon after one
var _hold_hint_done := false       # "Hold to order a fighting unit" was said this battle
var place_on := false
var _place_phase := 0        # the sim phase the ghost was placed in (deployment or battle; a change drops it)
var place_kind := ""               # "line" | "group"
var place_c := Vector2.ZERO        # world px: the front rank's middle (a group: the tap point)
var place_face := 0                # 0..1023
var place_len := 0.0               # a line: world px
var place_run := false
var place_exact := false           # a line that was never widened: the unit's own files
var place_clamped := false
var _place_run_touched := false
var _place_rel: Array = []         # a group: [{unit, rel (sim units), face0, files}]
var _place_ref := 0                # a group: the facing its relative places were measured at
var _place_layout: Array = []
var _place_drag := -1              # the handle held (Overlay.PH_*), -1 none
var _place_grab := Vector2.ZERO
var _place_face0 := 0              # the facing when the front handle was taken
var _place_moved := false
var _place_tick := -1
var _place_zoom := 1.0
var _demo_place := ""              # --demo-place=: the ghost to put up
var _demo_place_frames := 0
var _place_sel: Array[int] = []    # the selection the ghost was placed for
var _order_tag := ""               # the next order batch's name for the Undo toast ("line, 60 m")


## Orders are confirmed now: Confirm orders is on (or auto after a touch), units are selected, the battle runs.
func _confirm_on() -> bool:
	return interactive and (sim.phase == BattleSim.PHASE_BATTLE or sim.phase == BattleSim.PHASE_DEPLOY) \
		and _exit_timer <= 0.0 and not selection.is_empty() and ConfirmOrders.active(_last_touch)


func _place_connect() -> void:
	hud.place_go_pressed.connect(_place_go)
	hud.place_run_toggled.connect(func(on: bool):
		place_run = on
		_place_run_touched = true
		_count("place_run"))
	hud.place_waypoint_pressed.connect(_place_waypoint)
	hud.place_cancel_pressed.connect(func():
		_count("place_cancel")
		_place_clear())


func _place_clear() -> void:
	if not place_on and _place_drag < 0:
		return
	place_on = false
	_place_drag = -1
	_place_layout = []
	overlay.place_on = false
	overlay.place_layout = []
	overlay.place_handles = []
	overlay.place_hot = -1
	overlay.place_note = ""
	hud.set_place_bar(false)
	overlay.queue_redraw()


## Whether every selected unit (guns apart) already runs: the Run toggle's start.
func _place_run_start() -> bool:
	var any := false
	for u in selection:
		if sim.u_state[u] != BattleSim.U_READY or UT.cls(sim.u_type[u]) == UT.CLS_ART:
			continue
		if orders.value(u, "run") == 0:
			return false
		any = true
	return any


func _place_open() -> void:
	if not place_on:
		place_on = true
		_place_phase = sim.phase
		_place_sel = selection.duplicate()
		place_run = _place_run_start()
		_place_run_touched = false
	_place_refresh()


## A tap on the ground (the hook in _tap) with Confirm orders on: place the ghost there, facing the way the men would
## travel. The second tap of a double lights the ghost's Run instead.
func _place_from_tap(w: Vector2, double: bool) -> void:
	if double and place_on:
		place_run = true
		_place_run_touched = true
		_count("place_double")
		_place_refresh()
		return
	_count("place_tap")
	var app := _wp_append()
	var dest := w / PX_PER_M * M
	var at := {}
	for u in selection:
		if sim.u_state[u] == BattleSim.U_READY:
			at[u] = orders.chain_end(u) if app else Vector3i(orders.value(u, "ax"), orders.value(u, "ay"), orders.value(u, "face"))
	if at.is_empty():
		return
	var ids: Array = at.keys()
	var cx := 0.0
	var cy := 0.0
	for u in ids:
		cx += (at[u] as Vector3i).x
		cy += (at[u] as Vector3i).y
	cx /= ids.size()
	cy /= ids.size()
	var prim: int = selected if at.has(selected) else int(ids[0])
	var ref: int = (at[prim] as Vector3i).z
	var d := dest - Vector2(cx, cy)
	var turn := 0
	if d.length_squared() > 4.0 * M * M:
		var want := int(round(atan2(d.y, d.x) * 1024.0 / TAU)) & 1023
		turn = ((want - ref + 512) & 1023) - 512
	place_c = w
	place_face = (ref + turn) & 1023
	place_clamped = false
	if ids.size() == 1:
		place_kind = "line"
		place_exact = true
		place_len = maxf(float(BattleSim.files_to_width(orders.value(prim, "files"), sim.u_type[prim])) / M, MIN_LINE_M) * PX_PER_M
		place_len = minf(place_len, maxf(overlay.max_line_px(), MIN_LINE_M * PX_PER_M))
	else:
		place_kind = "group"
		_place_ref = ref
		_place_rel = []
		for u in ids:
			var e: Vector3i = at[u]
			_place_rel.append({"unit": u, "rel": Vector2(e.x - cx, e.y - cy), "face0": e.z, "files": orders.value(u, "files")})
	_place_open()


## A line drag that ended (the hook in _finish_line) with Confirm orders on: the line is the ghost.
func _place_from_line() -> void:
	_count("place_line")
	var d: Vector2 = overlay.preview_b - overlay.preview_a
	place_kind = "line"
	place_exact = false
	place_c = (overlay.preview_a + overlay.preview_b) * 0.5
	place_len = d.length()
	place_clamped = overlay.preview_clamped
	place_face = int(round((atan2(d.y, d.x) - PI * 0.5) * 1024.0 / TAU)) & 1023
	_place_open()


## The ghost's footprints (the sim's own order rules via the overlay's line layout, or the group's shape), the handles, the
## toolbar; called on every change and now and then (units die, break and shrink).
func _place_refresh() -> void:
	if not place_on:
		return
	_place_tick = sim.tick
	_place_zoom = camera.zoom.x
	var ang := place_face * TAU / 1024.0
	var fwd := Vector2(cos(ang), sin(ang))
	var right := Vector2(-fwd.y, fwd.x)
	_place_layout = []
	if place_kind == "line":
		place_len = clampf(place_len, MIN_LINE_M * PX_PER_M, maxf(overlay.max_line_px(), MIN_LINE_M * PX_PER_M))
		overlay.preview_a = place_c - right * place_len * 0.5
		overlay.preview_b = place_c + right * place_len * 0.5
		overlay.preview_ok = true
		place_clamped = overlay.max_line_px() > 0.0 and place_len >= overlay.max_line_px() - 0.5
		overlay.zoom = camera.zoom.x
		for p in overlay.preview_group():
			var q: Dictionary = (p as Dictionary).duplicate()
			q["facing"] = place_face
			if place_exact and overlay.selected_units.size() == 1:
				var pu: int = q["unit"]
				q["files"] = orders.value(pu, "files")
				q["width"] = BattleSim.files_to_width(int(q["files"]), sim.u_type[pu])
			_place_layout.append(q)
	else:
		var turn := ((place_face - _place_ref + 512) & 1023) - 512
		var rot := turn * TAU / 1024.0
		for r in _place_rel:
			var u: int = r["unit"]
			if sim.u_state[u] != BattleSim.U_READY:
				continue
			var pos: Vector2 = place_c + (r["rel"] as Vector2).rotated(rot) / M * PX_PER_M
			_place_layout.append({"unit": u, "centre": pos, "facing": (int(r["face0"]) + turn) & 1023,
				"width": BattleSim.files_to_width(int(r["files"]), sim.u_type[u]), "files": int(r["files"])})
	if _place_layout.is_empty():
		_place_clear()
		return
	var hr := Overlay.PLACE_R / camera.zoom.x
	var handles: Array = [{"id": Overlay.PH_BODY, "pos": place_c}]
	var reach := 0.0
	for p in _place_layout:
		reach = maxf(reach, ((p["centre"] as Vector2) - place_c).dot(fwd))
	handles.append({"id": Overlay.PH_FRONT, "pos": place_c + fwd * (reach + hr * 3.4)})
	if place_kind == "line":
		handles.append({"id": Overlay.PH_END_A, "pos": place_c - right * place_len * 0.5})
		handles.append({"id": Overlay.PH_END_B, "pos": place_c + right * place_len * 0.5})
	overlay.place_on = true
	overlay.place_kind = place_kind
	overlay.place_layout = _place_layout
	overlay.place_handles = handles
	overlay.place_face = place_face
	overlay.place_clamped = place_clamped
	overlay.queue_redraw()
	if sim.phase == BattleSim.PHASE_DEPLOY:
		_place_zone_fit()
	hud.set_place_bar(true, place_run, sim.phase != BattleSim.PHASE_DEPLOY, sim.phase != BattleSim.PHASE_DEPLOY)


## Deployment: each footprint of the ghost shows where its unit will stand, the sim's own rule (a placement outside the side's
## zone goes to the nearest point of it; a unit that can man a wall snaps to the wall; refused in a settlement zone's
## outside: marked "refused", left where it is, not sent).
func _place_zone_fit() -> void:
	for q in _place_layout:
		var u: int = q["unit"]
		var c: Vector2 = q["centre"] / PX_PER_M * M
		if BattleSim.can_man_walls(sim, u) and BattleSim.wall_snap(sim, int(c.x), int(c.y)).z >= 0:
			continue
		var zp := BattleSim.deploy_clamp(sim, sim.u_side[u], int(c.x), int(c.y))
		if zp.z == 0:
			q["refused"] = true
		else:
			q["centre"] = Vector2(zp.x, zp.y) / M * PX_PER_M


## Which handle (Overlay.PH_*) is under screen point sp, or -1. The small ones win over the body.
func _place_hit(sp: Vector2) -> int:
	if not place_on:
		return -1
	var r := Overlay.PLACE_R * (1.8 if _last_touch else 1.3)
	var best := -1
	var best_d := 1e9
	for h in overlay.place_handles:
		var id: int = h["id"]
		var d := world_to_screen(h["pos"]).distance_to(sp)
		if d > r:
			continue
		if d < best_d:   # (the nearest handle's centre wins where the circles overlap)
			best_d = d
			best = id
	return best


func _place_press(sp: Vector2) -> int:
	if not place_on or not _confirm_on():
		return -1
	var id := _place_hit(sp)
	_place_moved = false
	if id < 0:
		return -1
	_place_grab = place_c - _screen_to_world(sp)
	_place_face0 = place_face
	overlay.place_hot = id
	overlay.queue_redraw()
	return id


func _place_drag_to(sp: Vector2) -> void:
	var w := _screen_to_world(sp)
	_place_moved = true
	var ang := place_face * TAU / 1024.0
	var fwd := Vector2(cos(ang), sin(ang))
	var right := Vector2(-fwd.y, fwd.x)
	match _place_drag:
		Overlay.PH_BODY:
			place_c = (w + _place_grab).clamp(Vector2.ZERO, BoardView.field_px)
			_count("place_move")
		Overlay.PH_FRONT:
			var v := w - place_c
			if v.length() > 3.0:
				place_face = _place_snap(rad_to_deg(atan2(v.y, v.x)))
			_count("place_turn")
		Overlay.PH_END_A, Overlay.PH_END_B:
			var sgn := 1.0 if _place_drag == Overlay.PH_END_B else -1.0
			var other := place_c - right * sgn * place_len * 0.5
			var nl := clampf(sgn * (w - other).dot(right), MIN_LINE_M * PX_PER_M, maxf(overlay.max_line_px(), MIN_LINE_M * PX_PER_M))
			place_len = nl
			place_c = other + right * sgn * nl * 0.5
			place_exact = false
			_count("place_width")
	_place_refresh()


## Degrees (the finger's direction) to a facing: a stop at the facing the ghost had and at facing the nearest enemy
## (within PLACE_DETENT_DEG), else the nearest PLACE_SNAP_DEG step.
func _place_snap(deg: float) -> int:
	var cands: Array = [[rad_to_deg(_place_face0 * TAU / 1024.0), "as it stood"]]
	var best := -1
	var best_d := 0.0
	for u in sim.n_units:
		if sim.u_side[u] == player_side or sim.u_state[u] >= BattleSim.U_DESTROYED or sim.hidden_from(u, player_side):
			continue
		var d := (Vector2(sim.u_cx[u], sim.u_cy[u]) / M * PX_PER_M).distance_squared_to(place_c)
		if best < 0 or d < best_d:
			best = u
			best_d = d
	if best >= 0:
		var ev := Vector2(sim.u_cx[best], sim.u_cy[best]) / M * PX_PER_M - place_c
		cands.append([rad_to_deg(atan2(ev.y, ev.x)), "facing the enemy"])
	overlay.place_note = ""
	var out := deg
	var stopped := false
	for c in cands:
		if absf(wrapf(deg - float(c[0]), -180.0, 180.0)) <= PLACE_DETENT_DEG:
			out = float(c[0])
			overlay.place_note = str(c[1])
			stopped = true
			break
	if not stopped:
		out = roundf(deg / PLACE_SNAP_DEG) * PLACE_SNAP_DEG
	return int(round(out * 1024.0 / 360.0)) & 1023


## The finger lifted from a handle: a drag ends; a still tap on it is a tap on the ghost (the second of a double lights Run).
func _place_release(double: bool, now: float, pos: Vector2) -> void:
	_place_drag = -1
	overlay.place_hot = -1
	overlay.place_note = ""
	overlay.queue_redraw()
	if _place_moved:
		return
	if double:
		_last_tap_time = -10.0
		if place_on:
			place_run = true
			_place_run_touched = true
			_place_refresh()
	else:
		_last_tap_time = now
		_last_tap_pos = pos


## Go: one move order for each unit of the ghost (a waypoint when the chain tool is on), then the selection clears.
func _place_go() -> void:
	if not place_on or _place_layout.is_empty():
		return
	_count("place_go")
	_place_send(false)
	_place_clear()
	_select(-1)   # (also ends the waypoint tool: it goes off when the selection changes)


## Waypoint: the ghost becomes the next stop after the current move; the tool stays open for the next one.
func _place_waypoint() -> void:
	if not place_on or _place_layout.is_empty():
		return
	_count("place_waypoint")
	if not waypoint_mode:
		waypoint_mode = true
		_wp_sel = selection.duplicate()
		_count("wp_on")
	_place_send(true)
	_place_clear()
	_refresh_actions()


func _place_send(as_stop: bool) -> void:
	_order_tag = "line, %d m" % int(round(place_len / PX_PER_M)) if place_kind == "line" and not place_exact else "move"
	for p in _place_layout:
		var u: int = p["unit"]
		var c: Vector2 = p["centre"] / PX_PER_M * M
		if p.get("refused", false):
			_count("place_refused")
			overlay.flash("Place your units in the blue zone", p["centre"])
			continue
		var why: String = orders.wall_refusal(u, int(c.x), int(c.y))
		if why != "":
			_count("wall_refused")
			overlay.flash(why, p["centre"])
			continue
		var run := 1 if place_run else (0 if _place_run_touched else orders.value(u, "run"))
		var mo := BattleSim.make_move_order(0, u, int(c.x), int(c.y), p["facing"], p["width"], run)
		if as_stop or _wp_append():
			_wp_queue_append(mo, p["centre"])
		else:
			_queue(mo)
	_order_tag = ""


## The hook in _tap for a tap on the ground: Confirm on places the ghost (returns true); Confirm off holds a fighting
## unit's order back until the tap is held (true: nothing is ordered).
func _ground_tap_hook(w: Vector2, double: bool) -> bool:
	if _confirm_on():
		_place_from_tap(w, double)
		return true
	if _rmb_order or not _last_touch or sim.phase != BattleSim.PHASE_BATTLE:
		return false
	var fighting := false
	for u in selection:
		if sim.u_state[u] == BattleSim.U_READY and sim.u_fighting[u] > 0:
			fighting = true
	if not fighting or Time.get_ticks_msec() / 1000.0 - _press_sec >= HOLD_ORDER_SEC:
		return false
	_count("hold_to_order")
	if not _hold_hint_done:
		_hold_hint_done = true
		overlay.flash("Hold to order a fighting unit", w)
	return true


func _place_process() -> void:
	if _demo_place != "":
		_demo_place_frames += 1
		if _demo_place_frames > 6 and sim.phase == BattleSim.PHASE_BATTLE and selected >= 0:
			var pf := _demo_place.split(",")
			_demo_place = ""
			_place_from_tap(Vector2(sim.u_cx[selected], sim.u_cy[selected]) / M * PX_PER_M + Vector2(float(pf[0]), float(pf[1])) * PX_PER_M, false)
			if pf.size() > 2:
				place_face = int(round(float(pf[2]) * 1024.0 / 360.0)) & 1023
				_place_refresh()
	if place_on:
		if not _confirm_on() or _place_phase != sim.phase:
			_place_clear()
		elif (sim.tick != _place_tick and sim.tick % 5 == 0 and _place_drag < 0) or camera.zoom.x != _place_zoom:
			_place_refresh()
	var toast: bool = hud.undo_toast != null and hud.undo_wanted()
	if place_on or toast:
		var avoid := PackedVector2Array()
		for h in overlay.place_handles:
			avoid.append(world_to_screen(h["pos"]))
		hud.layout_floaters(world_to_screen(place_c), avoid)


## The Undo toast's words: "Pike 4: line, 60 m", "3 units: move".
func _undo_toast_text() -> String:
	if _undo_stack.is_empty():
		return ""
	var batch: Dictionary = _undo_stack.back()
	var recs: Array = batch["recs"]
	if recs.is_empty():
		return "Undo"
	var kind := str(batch.get("name", "order"))
	if recs.size() > 1:
		return "%d units: %s" % [recs.size(), kind]
	var u := int(recs[0]["u"])
	var short := str(UT.TYPES[sim.u_type[u]]["short"])
	var n := 0
	var idx := 0
	for k in sim.n_units:
		if sim.u_side[k] == sim.u_side[u] and sim.u_otype[k] == sim.u_otype[u]:
			n += 1
			if k <= u:
				idx = n
	return "%s%s: %s" % [short, (" %d" % idx) if n > 1 else "", kind]


func _undo_batch_name(order: Dictionary) -> String:
	if _order_tag != "":
		return _order_tag
	var t := int(order["type"])
	var nm := str(ORDER_NAMES.get(t, "order"))
	return {"run": "run or walk", "withdraw_all": "withdraw", "skirmish": "skirmish", "stance": "stance"}.get(nm, nm)
