extends Node3D
## The sea battle's 3D world (view only; docs/design/sea.md "The sea battle in 3D, stage D1"): built by SeaBattle._ready in place of its
## five Node2D layers and Camera2D when `--sea-view=3d` (or the web's `?sea-view=3d`) is set. It stands the sea on the same wooden table
## and lamp as the land battle (game/table3d.gd), draws the water and the land as flat quads with the 2D screen's own shader bodies
## (game/sea_water3d.gdshader, sea_coast3d.gdshader), every ship as a node (hull from game/sea_ship3d.gd, sails and flags rebuilt as she
## changes), the orders as ribbons on the water, and owns an orthographic camera of its own: target (a point of the sea), yaw, tilt and
## the height of the view in metres. 1 m of the sim is 1 m here: x east, z south (the sim's y), y up, the sea plane y 0.
##
## The contract (docs/design/sea.md): the view reads `host.sim` every frame and caches none, keys its per-ship nodes by the ship's
## index (a ship's index never changes), and never writes the sim or BoardView's statics. A frame leaves `sim.state_hash()` as it was
## (it only calls the pure `drive`, `heading`, `shot_range`); tests/sea3d_test.gd checks that.

const SeaSim := preload("res://sim/sea_sim.gd")
const ST := preload("res://sim/sea_types.gd")
const FM := preload("res://sim/fixed_math.gd")
const SeaKey := preload("res://game/sea_key.gd")
const SeaShip := preload("res://game/sea_ship3d.gd")
const Table3D := preload("res://game/table3d.gd")
const SeaCoast := preload("res://game/sea_coast3d.gd")
const SeaWake := preload("res://game/sea_wake3d.gd")
const Swell := preload("res://game/sea_swell3d.gd")
const Quality := preload("res://game/quality.gd")
const Oars := preload("res://game/sea_oars3d.gd")
const SHIP_SHADER := preload("res://game/sea_ship3d.gdshader")

const VIS3 := 2.0                  # toy scale (the owner, 2026-11-09): ships drawn twice their length; the 2D screen keeps its VIS 1.5
const MARGIN := 300.0              # the board's margin round the field (metres): the camera's clamp, the slab's edge
const TILT_MIN := 25.0
const TILT_MAX := 60.0
const TILT_OPEN := 45.0
const MAP_TILT := 85.0
const SIZE_MIN := 60.0             # the closest view: one frigate fills a phone (metres of the screen's height)
const ORDER_Y := 1.9               # the order ribbons ride this far over the water (clear of the swell)
const WAKE_EVERY := 0.3            # a wake point this often (seconds) ...
const WAKE_KEEP := 28              # ... and this many kept: a wake about 8 s long, over a ship length and a half at speed
const WAKES_EVERY := 0.05
const SPLINTER_CAP := 60
const RIG_EVERY := 0.05            # a ship's sails are rebuilt at most this often (seconds)

var host: Node
var look
var cam: Camera3D
var lamp: DirectionalLight3D
var env: Environment
var field := Vector2(2400, 1600)
var target := Vector2(1200, 800)   # the sea point at the screen's centre
var yaw := 0.0
var tilt := TILT_OPEN
var size := 800.0                  # the camera's orthographic height: metres of screen height
var follow := -1                   # the ship the camera follows (-1: none)
var map_view := false
var _map_prev := {}
var lamp_yaw := -1000.0
var water_mi: MeshInstance3D
var land_mi: MeshInstance3D       # the coast mesh (null: the field has no land)
var coast                          # SeaCoast: the land's stats, trees and kit pieces
var slab_mi: MeshInstance3D
var table_mi: MeshInstance3D
var orders_mi: MeshInstance3D
var wakes_mi: MeshInstance3D
var _wakes_mesh := ImmediateMesh.new()
var foam_mat: StandardMaterial3D   # the foam rings' and the wakes' material (null on Low: neither is drawn)
var splinters_mi: MultiMeshInstance3D
var _splinters: Array = []        # a ram blow's splinters: {p, v, age}
var _rng := RandomNumberGenerator.new()   # (the view's own: never the sim's)
var _wakes_t := -9.0
var wake_quads := 0               # (a count for the tests: the wake strips drawn this frame)
var bob_on := false               # the hulls bob and pitch on the CPU twin of the water's trains (not on Low)
var _orders_mesh := ImmediateMesh.new()
var ships: Array = []              # per ship (by index): {"root", "hull", "rig", "flags", "mat", "rig_buf", "flag_buf", "sig", "t", "heel"}
var _clock := 0.0
var _vp := Vector2(1280, 720)
var rig_builds := 0                # (a count for the tests: sail meshes rebuilt)
var wind_arrow_shown := false


func setup(p_host: Node) -> void:
	host = p_host
	look = host._look
	var sim = host.sim
	field = Vector2(sim.field_w, sim.field_h)
	target = field * 0.5
	size = maxf(field.x, field.y) * 0.4
	process_priority = 1000   # after the battle's _process
	var r := Table3D.build_env(self, false)
	env = r["env"]
	lamp = r["lamp"]
	look.materials3d()
	Swell.read_args()
	bob_on = not look.low
	_build_board()
	if bob_on:
		foam_mat = SeaWake.foam_material(SeaWake.foam_strip_texture())
		wakes_mi = MeshInstance3D.new()
		wakes_mi.mesh = _wakes_mesh
		wakes_mi.material_override = foam_mat
		wakes_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(wakes_mi)
	_build_ships()
	orders_mi = MeshInstance3D.new()
	orders_mi.mesh = _orders_mesh
	var om := StandardMaterial3D.new()
	om.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	om.vertex_color_use_as_albedo = true
	om.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	om.cull_mode = BaseMaterial3D.CULL_DISABLED
	om.render_priority = 2
	orders_mi.material_override = om
	orders_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(orders_mi)
	cam = Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	add_child(cam)
	cam.make_current()
	sync_camera()


# --------------------------------------------------------------------------------------------- the room

func _build_board() -> void:
	var m := MARGIN
	var x0 := -m
	var z0 := -m
	var x1 := field.x + m
	var z1 := field.y + m
	var foot := -Table3D.SLAB_BELOW
	table_mi = Table3D.table(Vector3(field.x * 0.5, foot - Table3D.TABLE_BELOW, field.y * 0.5), Vector4(x0, z0, x1, z1),
		maxf(field.x, field.y) * 3.0 + 2.0 * m)
	add_child(table_mi)
	var edges: Array = [
		[[Vector3(x0, 0, z0), Vector3(x1, 0, z0)], Vector3(0, 0, -1)],
		[[Vector3(x0, 0, z1), Vector3(x1, 0, z1)], Vector3(0, 0, 1)],
		[[Vector3(x0, 0, z0), Vector3(x0, 0, z1)], Vector3(-1, 0, 0)],
		[[Vector3(x1, 0, z0), Vector3(x1, 0, z1)], Vector3(1, 0, 0)]]
	slab_mi = MeshInstance3D.new()
	slab_mi.mesh = Table3D.slab_mesh(edges, foot)
	slab_mi.material_override = Table3D.slab_material(0.25, foot, null, Vector3(0.10, 0.36, 0.52))
	slab_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(slab_mi)
	var ctr := Vector3(field.x * 0.5, 0.0, field.y * 0.5)
	water_mi = MeshInstance3D.new()
	if look.low:
		var pm := PlaneMesh.new()
		pm.size = Vector2(field.x + 2.0 * m, field.y + 2.0 * m)
		water_mi.mesh = pm
		water_mi.position = ctr
	else:
		water_mi.mesh = Swell.grid_mesh(look, x0, z0, x1, z1)
	Swell.apply(look.water3d_mat, not look.low)
	water_mi.material_override = look.water3d_mat
	water_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(water_mi)
	# The land, D2: a relief mesh from the baked signed distance with the 2D shader's body, the trees as cards, the rocks, the ruin
	# and the harbour forts as the kit's meshes (game/sea_coast3d.gd); no mesh where the field has no land.
	coast = SeaCoast.new()
	land_mi = coast.build(self, look, field, m, look.land3d_mat, Table3D.lamp_basis().z)


## Stand the lamp in the room at yaw y (the opening yaw; as View3D.set_lamp).
func set_lamp(y: float) -> void:
	lamp_yaw = y
	lamp.transform = Transform3D(Basis(Vector3.UP, y) * Table3D.lamp_basis(), Vector3.ZERO)
	if coast != null and coast.kit_mat != null:
		coast.kit_mat.set_shader_parameter("key_dir", lamp.transform.basis.z)


# --------------------------------------------------------------------------------------------- the camera

func vp_size() -> Vector2:
	var s := get_viewport().get_visible_rect().size
	if s.x > 1.0 and s.y > 1.0:
		_vp = s
	return _vp


func cam_basis() -> Basis:
	return Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, -deg_to_rad(tilt))


func size_max() -> float:
	return maxf(field.x, field.y) + 2.0 * MARGIN


## Aim the camera: the transform, the ortho size and the near / far that hug the board.
func sync_camera() -> void:
	if cam == null:
		return
	size = clampf(size, SIZE_MIN, size_max())
	var b := cam_basis()
	var e := deg_to_rad(tilt)
	var dist := size_max() * 1.5 + 200.0
	cam.transform = Transform3D(b, Vector3(target.x, 0.0, target.y) + b.z * dist)
	cam.size = size
	var reach := size * 0.5 * cos(e) / maxf(sin(e), 0.1) + 90.0 / maxf(sin(e), 0.1) + 10.0
	cam.near = maxf(1.0, dist - reach)
	cam.far = dist + reach + 10.0


## Screen point -> the sea point under it (a ray against the sea plane y 0).
func world_at(screen: Vector2) -> Vector2:
	var vp := vp_size()
	var b := cam_basis()
	var ppm := vp.y / size
	var off := (screen - vp * 0.5) / ppm
	var p := Vector3(target.x, 0.0, target.y) + b.x * off.x - b.y * off.y
	var dy := -b.z.y
	var t := -p.y / dy
	var q := p + (-b.z) * t
	return Vector2(q.x, q.z)


## A sea point (at height h metres) -> its screen point.
func project(w: Vector2, h := 0.0) -> Vector2:
	var vp := vp_size()
	var b := cam_basis()
	var rel := Vector3(w.x - target.x, h, w.y - target.y)
	var ppm := vp.y / size
	return vp * 0.5 + Vector2(rel.dot(b.x), -rel.dot(b.y)) * ppm


func metres_per_px() -> float:
	return size / vp_size().y


func clamp_target() -> void:
	target = target.clamp(Vector2(-MARGIN, -MARGIN), field + Vector2(MARGIN, MARGIN))


func pan_px(d: Vector2) -> void:
	var c := vp_size() * 0.5
	target -= world_at(c + d) - world_at(c)
	follow = -1
	clamp_target()
	sync_camera()


func zoom_at(screen: Vector2, f: float) -> void:
	var before := world_at(screen)
	size = clampf(size / f, SIZE_MIN, size_max())
	sync_camera()
	target += before - world_at(screen)
	clamp_target()
	sync_camera()


## Turn by dyaw (radians) and tilt by dtilt (degrees) about the sea point under screen point `pivot`. In the map view a turn or a
## tilt down leaves it; a tilt up does nothing there.
func turn(dyaw: float, dtilt: float, pivot: Vector2) -> void:
	if map_view:
		if dyaw == 0.0 and dtilt >= 0.0:
			return
		map_leave(false)
	var g := world_at(pivot)
	yaw = wrapf(yaw + dyaw, -PI, PI)
	tilt = clampf(tilt + dtilt, TILT_MIN, TILT_MAX)
	sync_camera()
	target += g - world_at(pivot)
	clamp_target()
	sync_camera()


## The part of the screen the HUD leaves free, in pixels: x, y of its top left and the width and height. The top bar and the ship cards
## (left) and the orders bar (bottom) are not drawn through: a fit puts the ships inside this rectangle.
func safe_rect() -> Rect2:
	var vp := vp_size()
	var ins: Vector4 = host.hud_insets() if host.has_method("hud_insets") else Vector4(4, 4, 4, 4)
	return Rect2(ins.x, ins.y, maxf(vp.x - ins.x - ins.z, 50.0), maxf(vp.y - ins.y - ins.w, 50.0))


## Fit the view to `pts` (sea points) plus `pad` metres, at the current yaw and tilt, inside the HUD's free rectangle.
func fit(pts: Array, pad: float, min_size := 250.0) -> void:
	if pts.is_empty():
		return
	var right := Vector2(cos(yaw), -sin(yaw))
	var up := -Vector2(sin(yaw), cos(yaw))
	var lo := Vector2(1e9, 1e9)
	var hi := Vector2(-1e9, -1e9)
	for p in pts:
		var q := Vector2((p as Vector2).dot(right), (p as Vector2).dot(up))
		lo = lo.min(q)
		hi = hi.max(q)
	lo -= Vector2(pad, pad)
	hi += Vector2(pad, pad)
	var c := (lo + hi) * 0.5
	var vp := vp_size()
	var u := safe_rect()
	var e := deg_to_rad(tilt)
	size = maxf(maxf((hi.y - lo.y) * sin(e) * vp.y / u.size.y, (hi.x - lo.x) * vp.y / u.size.x), min_size)
	size = clampf(size, SIZE_MIN, size_max())
	var ppm := vp.y / size
	var uc := u.get_center()
	var ax := (uc.x - vp.x * 0.5) / ppm
	var ay := -(uc.y - vp.y * 0.5) / (ppm * maxf(sin(e), 0.1))
	target = right * (c.x - ax) + up * (c.y - ay)
	clamp_target()
	sync_camera()


## The opening camera: the player's fleet nearest the viewer (the table turned in quarter turns), the lamp stood at that yaw, both
## fleets in view.
func open() -> void:
	_open(true)


## Fit both fleets again at the current yaw and tilt (a shot's aid).
func open_fit() -> void:
	_open(false)


func _open(turn_table: bool) -> void:
	var sim = host.sim
	var mine := Vector2.ZERO
	var foe := Vector2.ZERO
	var nm := 0
	var nf := 0
	var pts: Array = []
	for s in sim.n_units:
		var p: Vector2 = host._pos(s)
		pts.append(p)
		if sim.u_side[s] == host.player_side:
			mine += p
			nm += 1
		else:
			foe += p
			nf += 1
	var y0 := yaw
	if turn_table and nm > 0 and nf > 0:
		var d := mine / nm - foe / nf
		if d.length() > 60.0:
			y0 = roundf(atan2(d.x, d.y) / (PI * 0.5)) * (PI * 0.5)
	var t0 := TILT_OPEN if turn_table else tilt
	if turn_table:
		y0 = y0 if nm > 0 and nf > 0 and (mine / nm - foe / nf).length() > 60.0 else 0.0
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--sea-yaw="):
				y0 = deg_to_rad(float(a.get_slice("=", 1)))
			elif a.begins_with("--sea-tilt="):
				t0 = clampf(float(a.get_slice("=", 1)), TILT_MIN, TILT_MAX)
	yaw = wrapf(y0, -PI, PI)
	tilt = t0
	if turn_table:
		set_lamp(yaw)
	fit(pts, 140.0)


func center_on(w: Vector2) -> void:
	target = w
	clamp_target()
	sync_camera()


func set_follow(s: int) -> void:
	follow = s
	if s >= 0:
		center_on(host._pos(s))


## The map camera: yaw 0, tilt 85, the whole field in view; again: the camera it replaced.
func map_set(on: bool) -> void:
	if on == map_view:
		return
	if on:
		_map_prev = {"yaw": yaw, "tilt": tilt, "size": size, "target": target}
		map_view = true
		yaw = 0.0
		tilt = MAP_TILT
		follow = -1
		fit([Vector2(0, 0), Vector2(field.x, 0), Vector2(0, field.y), field], 70.0, SIZE_MIN)
	else:
		map_leave(true)


func map_leave(restore: bool) -> void:
	if not map_view:
		return
	map_view = false
	if restore and not _map_prev.is_empty():
		yaw = float(_map_prev["yaw"])
		tilt = float(_map_prev["tilt"])
		size = float(_map_prev["size"])
		target = _map_prev["target"]
	else:
		tilt = TILT_MAX
	_map_prev = {}
	clamp_target()
	sync_camera()


# --------------------------------------------------------------------------------------------- picking

## The live ship whose projected centre is nearest the screen point within max(22 px, her hull's reach); -1: none.
func ship_at(screen: Vector2) -> int:
	var sim = host.sim
	var ppm := vp_size().y / size
	var best := -1
	var bd := 1e9
	for s in sim.n_units:
		var st: int = sim.u_state[s]
		if st == SeaSim.S_SUNK or st == SeaSim.S_FLED:
			continue
		var d := screen.distance_to(project(host._pos(s), 3.0))
		var r := maxf(float(ST.stat(sim.s_type[s], "len")) * 0.6 * VIS3 * ppm, 22.0)
		if d < r and d < bd:
			bd = d
			best = s
	return best


## The indices of the ships (of `side`, live) whose projected centre lies in the screen rectangle.
func ships_in_rect(r: Rect2, side: int) -> Array[int]:
	var sim = host.sim
	var out: Array[int] = []
	for s in sim.n_units:
		if sim.u_side[s] == side and sim.u_state[s] == SeaSim.S_SAIL and r.has_point(project(host._pos(s), 3.0)):
			out.append(s)
	return out


# --------------------------------------------------------------------------------------------- ships

func _build_ships() -> void:
	var sim = host.sim
	for n in ships:
		if n != null:
			(n["root"] as Node3D).queue_free()
			if n["ring"] != null:
				(n["ring"] as Node3D).queue_free()
	ships = []
	for s in sim.n_units:
		var ty: int = sim.s_type[s]
		var d: Dictionary = (host.scenario.get("units", []) as Array)[s]
		var gold := int(d.get("g", 0)) > 0
		var dm0 := SeaShip.dims(ty, VIS3)
		var mat := ShaderMaterial.new()
		mat.shader = SHIP_SHADER
		var root := Node3D.new()
		var hull := MeshInstance3D.new()
		var mk := SeaShip.model_key(ty)
		var hmat := mat
		if SeaShip.has_model(mk):
			# The row's model (tools/battlekit/export_ships.py): hull, deck, castles, gunports, ram; the rig stays dynamic.
			hull.mesh = SeaShip.model(mk)
			hmat = SeaShip.model_material(host._ship_col(s), gold)
			hull.scale = Vector3.ONE * (VIS3 / SeaShip.MODEL_VIS)
		else:
			hull.mesh = SeaShip.hull(ty, VIS3, host._ship_col(s), gold)
		hull.material_override = hmat
		hull.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(hull)
		var rig := MeshInstance3D.new()
		rig.mesh = ArrayMesh.new()
		rig.material_override = mat
		rig.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(rig)
		var fl := MeshInstance3D.new()
		fl.mesh = ArrayMesh.new()
		fl.material_override = mat
		fl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(fl)
		var oars: MultiMeshInstance3D = null
		var corvus: MeshInstance3D = null
		if ST.is_galley(ty) and Oars.pairs(ty) > 0:
			var omm := MultiMesh.new()
			omm.transform_format = MultiMesh.TRANSFORM_3D
			omm.mesh = Oars.oar_mesh()
			omm.instance_count = Oars.pairs(ty) * 2
			omm.custom_aabb = AABB(Vector3(-60, -10, -40), Vector3(120, 30, 80))
			oars = MultiMeshInstance3D.new()
			oars.multimesh = omm
			oars.material_override = mat
			oars.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(oars)
		if ST.stat(ty, "corvus") != 0:
			corvus = MeshInstance3D.new()
			corvus.material_override = mat
			corvus.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(corvus)
		add_child(root)
		var ring: MeshInstance3D = null
		if bob_on:
			ring = MeshInstance3D.new()
			ring.mesh = SeaWake.ring_mesh(ty, VIS3, 2.2 + float(dm0["bm"]) * 0.12)
			ring.material_override = foam_mat
			ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(ring)
		ships.append({"root": root, "hull": hull, "rig": rig, "flags": fl, "mat": mat, "hmat": hmat, "oars": oars, "corvus": corvus, "cv": 0.0, "cv_b": -9.0, "cv_yaw": 0.0, "ram_t": -9.0, "ring": ring, "wake": PackedVector2Array(), "wake_t": -1.0, "sig": -1, "t": -1.0, "heel": 0.0})


## The sim was replaced (a co-op session started or restored a snapshot): the sails are rebuilt from the new state.
func rebind() -> void:
	for n in ships:
		n["sig"] = -1
		n["t"] = -1.0
		n["heel"] = 0.0
		n["wake"] = PackedVector2Array()
	follow = -1


func _wind_local(sim, h: float) -> Vector2:
	var a: float = (sim.w_from + 512) * TAU / 1024.0
	return Vector2(cos(a - h), sin(a - h))


func _update_ship(s: int, dt: float) -> void:
	var sim = host.sim
	var n: Dictionary = ships[s]
	var root: Node3D = n["root"]
	var st: int = sim.u_state[s]
	var age_end: float = (sim.tick - sim.s_end_t[s]) * 0.1 if sim.s_end_t[s] >= 0 else 0.0
	var sink := 0.0
	if st == SeaSim.S_FLED or (st == SeaSim.S_SUNK and (sim.s_blown[s] != 0 or age_end > 6.0)):
		root.visible = false
		if n["ring"] != null:
			(n["ring"] as Node3D).visible = false
		return
	if st == SeaSim.S_SUNK:
		sink = clampf(age_end / 6.0, 0.0, 1.0)
	root.visible = true
	var ty: int = sim.s_type[s]
	var dm := SeaShip.dims(ty, VIS3)
	var p: Vector2 = host._draw_pos(s)
	var h: float = host._head(s) + sink * 0.5
	var wtl := _wind_local(sim, h)
	var sailing: bool = st == SeaSim.S_SAIL and sim.s_sail[s] != 0 and ST.stat(ty, "oars") == 0
	var drv := 0.0
	if ST.stat(ty, "oars") == 0 and st == SeaSim.S_SAIL:
		drv = clampf(float(sim.drive(s, sim.heading(s))) / 100.0, 0.0, 1.2)
	var heel_t := 0.0
	if sailing:
		heel_t = 0.11 * minf(drv, 1.0) * clampf(absf(wtl.y) * 1.4, 0.0, 1.0) * signf(wtl.y)
	n["heel"] = lerpf(float(n["heel"]), heel_t, minf(1.0, dt * 3.0))
	var roll: float = float(n["heel"]) + sink * 0.55
	var wv := Vector3.ZERO
	if bob_on and st != SeaSim.S_SUNK:
		wv = Swell.ride(p, host._head(s), look._clock, look._wind_dir(), look._wstr(sim), look.sdf_at(p))
	var pitch := wv.y
	roll += wv.z
	root.transform = Transform3D(Basis(Vector3.UP, -h) * Basis(Vector3.RIGHT, roll) * Basis(Vector3(0, 0, 1), sink * 0.3 + pitch),
		Vector3(p.x, wv.x - sink * (float(dm["fb"]) + 2.5), p.y))
	if n["oars"] != null:
		Oars.sweep((n["oars"] as MultiMeshInstance3D).multimesh, ty, VIS3, Oars.rate(sim, s), _clock)
	if n["corvus"] != null:
		var o: int = sim.s_grap[s]
		var dropped: bool = o >= 0 and sim.s_boarder[s] != 0 and sim.tick - sim.s_cv_t[s] >= SeaSim.CORVUS_COOL
		n["cv"] = move_toward(float(n["cv"]), 1.0 if dropped else 0.0, dt * 2.5)
		if dropped:
			var dd: Vector2 = host._pos(o) - host._pos(s)
			n["cv_yaw"] = wrapf(atan2(dd.y, dd.x) - host._head(s), -PI, PI)
		if absf(float(n["cv"]) - float(n["cv_b"])) > 0.03 or (dropped and absf(wrapf(float(n["cv_yaw"]) - float(n["cv_yb"] if n.has("cv_yb") else 9.0), -PI, PI)) > 0.05):
			n["cv_b"] = n["cv"]
			n["cv_yb"] = n["cv_yaw"]
			(n["corvus"] as MeshInstance3D).mesh = Oars.corvus_mesh(ty, VIS3, float(n["cv"]), float(n["cv_yaw"]))
	if n["ring"] != null:
		var rg: MeshInstance3D = n["ring"]
		rg.visible = sink < 0.2 and st != SeaSim.S_SUNK
		var pulse := 1.0 + 0.9 * clampf(1.0 - (_clock - float(n["ram_t"])) / 1.2, 0.0, 1.0)   # a ram blow's bow wave: the ring swells and settles
		rg.transform = Transform3D(Basis(Vector3.UP, -h) * Basis(Vector3.RIGHT, wv.z) * Basis(Vector3(0, 0, 1), wv.y) * Basis.from_scale(Vector3(pulse, 1.0, pulse)),
			Vector3(p.x, SeaWake.RING_Y + wv.x, p.y))
	var fire := ST.is_fire(ty)
	var tint := 1.0
	if st == SeaSim.S_STRUCK or st == SeaSim.S_TAKEN:
		tint = 0.88
	if fire and sim.s_lit[s] >= 0:
		tint = 0.55
	(n["mat"] as ShaderMaterial).set_shader_parameter("tint", Vector3(tint, tint, tint))
	if n["hmat"] != n["mat"]:
		(n["hmat"] as ShaderMaterial).set_shader_parameter("tint", Vector3(tint, tint, tint))
	# The rig, when the ship's state changed enough (and not oftener than RIG_EVERY).
	var rigf := float(sim.s_rig[s]) / maxi(sim.s_rig0[s], 1)
	var furled: bool = sim.s_sail[s] == 0 or st != SeaSim.S_SAIL
	var hh: int = sim.heading(s)
	var rel: int = FM.angle_diff(hh, (sim.w_from + 512) & 1023)
	var sig := int(rel / 8) * 1000003 + int(drv * 10.0) * 10007 + int(rigf * 20.0) * 101 + (1 if furled else 0) * 7 + st * 3
	if sig != int(n["sig"]) and _clock - float(n["t"]) >= RIG_EVERY:
		n["sig"] = sig
		n["t"] = _clock
		var b := SeaShip.Buf.new()
		var offw := absi(FM.angle_diff(hh, sim.w_from))
		var swing := clampf((512 - offw) * 0.45, 20.0, 230.0) * TAU / 1024.0
		var lee := 1.0 if FM.angle_diff(hh, sim.w_from) < 0 else -1.0
		SeaShip.rig(b, ty, VIS3, rigf, furled, float(rel), drv, wtl, s, lee, swing)
		b.mesh((n["rig"] as MeshInstance3D).mesh as ArrayMesh)
		rig_builds += 1
	# The flags, every frame: her colour, white struck, the captor's when taken.
	var col: Color = host._ship_col(s)
	var ens := col
	if st == SeaSim.S_STRUCK:
		ens = Color(0.97, 0.97, 0.97)
	elif st == SeaSim.S_TAKEN and sim.s_by[s] >= 0:
		ens = host._side_col(sim.s_by[s])
	var fb := SeaShip.Buf.new()
	SeaShip.flags(fb, ty, VIS3, wtl, ens, col, _clock, s, st == SeaSim.S_SAIL and sink == 0.0)
	fb.mesh((n["flags"] as MeshInstance3D).mesh as ArrayMesh)


## The wake strips of every ship still afloat (the host's wake points, the ship's place appended).
func _update_wakes() -> void:
	if not bob_on:
		return
	if _clock - _wakes_t < WAKES_EVERY and wake_quads > 0:
		return   # (the ribbons are rebuilt at 20 Hz: the ships move a metre or two between)
	_wakes_t = _clock
	var sim = host.sim
	var list: Array = []
	for s in mini(sim.n_units, ships.size()):
		var st: int = sim.u_state[s]
		if st == SeaSim.S_SUNK or st == SeaSim.S_FLED:
			continue
		var n: Dictionary = ships[s]
		var wk: PackedVector2Array = n["wake"]
		var now: Vector2 = host._draw_pos(s)
		if st == SeaSim.S_SAIL and (wk.is_empty() or (_clock - float(n["wake_t"]) >= WAKE_EVERY and now.distance_to(wk[wk.size() - 1]) > 0.5)):
			wk.append(now)
			n["wake_t"] = _clock
			if wk.size() > WAKE_KEEP:
				wk.remove_at(0)
			n["wake"] = wk
		elif st != SeaSim.S_SAIL and not wk.is_empty() and _clock - float(n["wake_t"]) >= WAKE_EVERY:
			wk.remove_at(0)   # (a ship hove to or struck lets her wake die away)
			n["wake_t"] = _clock
			n["wake"] = wk
		if wk.size() < 1:
			continue
		var pts := wk.duplicate()
		pts.append(now)
		var ty: int = sim.s_type[s]
		list.append({"pts": pts, "beam": float(ST.stat(ty, "beam")) * VIS3 * 0.6,
			"speed": clampf(float(sim.s_spd[s]) / maxf(float(ST.stat(ty, "vmax")) * 10.24, 1.0), 0.0, 1.0), "heading": host._head(s)})
	var wd: Vector2 = look._wind_dir()
	var ws: float = look._wstr(sim)
	var lift := func(q: Vector2) -> float:
		return Swell.sample(q, look._clock, wd, ws, smoothstep(8.0, 120.0, look.sdf_at(q))).x
	wake_quads = SeaWake.build_wakes(_wakes_mesh, list, lift)


## Quality Auto's mid-battle downgrade (game/sea_battle.gd measures the first 3 s): the swell, the bob, the foam rings and the wakes go,
## the water becomes the flat quad with the 2D Low's still wash. (A battle that opened on Low never built them.)
func apply_quality() -> void:
	if not bob_on or not Quality.is_low():
		return
	bob_on = false
	var m := MARGIN
	var pm := PlaneMesh.new()
	pm.size = Vector2(field.x + 2.0 * m, field.y + 2.0 * m)
	water_mi.mesh = pm
	water_mi.position = Vector3(field.x * 0.5, 0.0, field.y * 0.5)
	look.water3d_mat.set_shader_parameter("hi", 0.0)
	Swell.apply(look.water3d_mat, false)
	if wakes_mi != null:
		wakes_mi.visible = false
	for n in ships:
		if n["ring"] != null:
			(n["ring"] as Node3D).visible = false
		(n["root"] as Node3D).position.y = 0.0


## A ram blow (SeaSim.EV_RAM, a the rammer, c the struck): a crunch of splinters at the rammer's bow and the struck hull's ring swelling.
func on_ram(a: int, c: int) -> void:
	if a < 0 or a >= ships.size():
		return
	var sim = host.sim
	var ty: int = sim.s_type[a]
	var h: float = host._head(a)
	var bow: Vector2 = host._pos(a) + Vector2(cos(h), sin(h)) * float(SeaShip.dims(ty, VIS3)["ln"]) * 0.5
	for k in 20:
		var ang := _rng.randf() * TAU
		var sp := 3.0 + _rng.randf() * 7.0
		_splinters.append({"p": Vector3(bow.x, 1.0 + _rng.randf() * 1.5, bow.y), "v": Vector3(cos(ang) * sp, 5.0 + _rng.randf() * 9.0, sin(ang) * sp), "age": 0.0})
	if _splinters.size() > SPLINTER_CAP:
		_splinters = _splinters.slice(_splinters.size() - SPLINTER_CAP)
	for s in [a, c]:
		if s >= 0 and s < ships.size():
			ships[s]["ram_t"] = _clock


func _update_splinters(dt: float) -> void:
	if splinters_mi == null:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		var b := SeaShip.Buf.new()
		b.box(Vector3.ZERO, 1.1, 0.25, 0.25, Color(0.66, 0.48, 0.26))
		mm.mesh = b.mesh()
		mm.instance_count = SPLINTER_CAP
		mm.visible_instance_count = 0
		mm.custom_aabb = AABB(Vector3(-100, -5, -100), Vector3(field.x + 200, 80, field.y + 200))
		splinters_mi = MultiMeshInstance3D.new()
		splinters_mi.multimesh = mm
		var mat := ShaderMaterial.new()
		mat.shader = SHIP_SHADER
		splinters_mi.material_override = mat
		splinters_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(splinters_mi)
	var live: Array = []
	for sp in _splinters:
		sp["age"] += dt
		var v: Vector3 = sp["v"]
		v.y -= 22.0 * dt
		sp["v"] = v
		var p: Vector3 = sp["p"] + v * dt
		if p.y < 0.0 or float(sp["age"]) > 1.8:
			continue
		sp["p"] = p
		live.append(sp)
	_splinters = live
	var mm2: MultiMesh = splinters_mi.multimesh
	for i in live.size():
		var sp2: Dictionary = live[i]
		var spin := float(sp2["age"]) * 9.0 + i
		mm2.set_instance_transform(i, Transform3D(Basis(Vector3(1, 0.3, 0.2).normalized(), spin), sp2["p"]))
	mm2.visible_instance_count = live.size()


func update(delta: float) -> void:
	_clock += delta
	var sim = host.sim
	if follow >= 0:
		if follow >= sim.n_units or sim.u_state[follow] != SeaSim.S_SAIL:
			follow = -1
		else:
			var p: Vector2 = host._pos(follow)
			target = target.lerp(p, minf(1.0, delta * 6.0))
			clamp_target()
	sync_camera()
	for s in mini(sim.n_units, ships.size()):
		_update_ship(s, delta)
	_update_wakes()
	_update_splinters(delta)
	_draw_orders()


# --------------------------------------------------------------------------------------------- the orders on the water

## Ribbon builder for the order lines (flat quads at ORDER_Y, `mpp` metres a screen pixel).
class Lines:
	extends RefCounted
	var mesh: ImmediateMesh
	var mpp := 1.0
	var y := 0.4
	var verts: Array = []
	var cols: PackedColorArray = PackedColorArray()

	func seg(a: Vector2, b: Vector2, c: Color, px: float) -> void:
		var d := b - a
		if d.length() < 0.01:
			return
		var w := px * mpp * 0.5
		var pr := Vector2(-d.y, d.x).normalized() * w
		var p0 := a + pr
		var p1 := a - pr
		var p2 := b - pr
		var p3 := b + pr
		for q in [p0, p1, p2, p0, p2, p3]:
			verts.append(Vector3((q as Vector2).x, y, (q as Vector2).y))
			cols.append(c)

	func dashed(a: Vector2, b: Vector2, c: Color, px: float, dash_px: float) -> void:
		var d := a.distance_to(b)
		var dash := dash_px * mpp
		if d < 1.0 or dash <= 0.0:
			return
		var n := int(d / (dash * 2.0)) + 1
		for i in mini(n, 400):
			var t0 := float(i) * dash * 2.0 / d
			var t1 := minf(t0 + dash / d, 1.0)
			seg(a.lerp(b, t0), a.lerp(b, t1), c, px)

	func arc(ctr: Vector2, r: float, a0: float, a1: float, n: int, c: Color, px: float) -> void:
		var prev := ctr + Vector2(cos(a0), sin(a0)) * r
		for i in range(1, n + 1):
			var a := lerpf(a0, a1, float(i) / n)
			var p := ctr + Vector2(cos(a), sin(a)) * r
			seg(prev, p, c, px)
			prev = p

	func dot(ctr: Vector2, r_px: float, c: Color) -> void:
		var r := r_px * mpp
		for i in 6:
			var a0 := TAU * float(i) / 6.0
			var a1 := TAU * float(i + 1) / 6.0
			for q in [ctr, ctr + Vector2(cos(a0), sin(a0)) * r, ctr + Vector2(cos(a1), sin(a1)) * r]:
				verts.append(Vector3((q as Vector2).x, y, (q as Vector2).y))
				cols.append(c)

	func commit() -> void:
		mesh.clear_surfaces()
		if verts.is_empty():
			return
		mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
		for i in verts.size():
			mesh.surface_set_color(cols[i])
			mesh.surface_add_vertex(verts[i])
		mesh.surface_end()


func _draw_orders() -> void:
	var sim = host.sim
	var L := Lines.new()
	L.mesh = _orders_mesh
	L.mpp = metres_per_px()
	L.y = ORDER_Y
	var player: int = host.player_side
	var vis: float = VIS3
	for s in sim.n_units:
		if sim.u_side[s] != player or sim.u_state[s] != SeaSim.S_SAIL:
			continue
		var sel: bool = host.selection.has(s)
		var al := 0.9 if sel else 0.35
		var p: Vector2 = host._pos(s)
		var flag: Color = host._side_col(sim.u_side[s])
		match sim.s_mode[s]:
			SeaSim.M_GOTO:
				var g := Vector2(sim.s_tx[s], sim.s_ty[s]) / 1024.0
				var pts: PackedVector2Array = host.course_points(s)
				for i in range(1, pts.size()):
					L.dashed(pts[i - 1], pts[i], SeaKey.col("course", flag, al), 2.4, 10.0)
				L.arc(g, 9.0 * L.mpp + 3.0, 0, TAU, 20, SeaKey.col("waypoint", flag, al), 2.4)
				if pts.size() > 2:
					L.dot(pts[1], 4.0, SeaKey.col("course", flag, al))
			SeaSim.M_ENGAGE, SeaSim.M_BOARD:
				var t: int = sim.s_tgt[s]
				if t >= 0:
					var tp: Vector2 = host._pos(t)
					var c := SeaKey.col("attack" if sim.s_mode[s] == SeaSim.M_ENGAGE else "board", Color.WHITE, al)
					L.dashed(p, tp, c, 2.4, 8.0)
					var tl := float(ST.stat(sim.s_type[t], "len")) * vis
					L.arc(tp, tl * 0.62 + 6.0, 0, TAU, 28, c, 3.0)
			SeaSim.M_FIRE:
				var tf: int = sim.s_tgt[s]
				if tf >= 0:
					var tpf: Vector2 = host._pos(tf)
					var cf := SeaKey.col("fire", Color.WHITE, al)
					L.dashed(p, tpf, cf, 3.0, 6.0)
					L.arc(tpf, float(ST.stat(sim.s_type[tf], "len")) * vis * 0.62 + 8.0, 0, TAU, 28, cf, 3.4)
					if sim.s_lit[s] < 0:
						L.arc(p, float(SeaSim.FS_LIGHT_M), 0, TAU, 48, SeaKey.col("fire", Color.WHITE, al * 0.25), 2.0)
			SeaSim.M_FLEE:
				var fpts: PackedVector2Array = host.course_points(s)
				for i in range(1, fpts.size()):
					L.dashed(fpts[i - 1], fpts[i], SeaKey.col("flee", Color.WHITE, al * 0.8), 2.2, 6.0)
		if sel:
			# The selected ring, and both broadsides' arcs and reach, loaded (bright) or reloading (dim).
			var ln := float(ST.stat(sim.s_type[s], "len")) * vis
			L.arc(p, ln * 0.62 + 4.0, 0, TAU, 40, SeaKey.col("selected", flag, 0.95), 3.2)
			for k in broadside_arcs(s):
				var ac := SeaKey.col("arcs", Color.WHITE, 0.4 if k["loaded"] else 0.12)
				var ctr: float = k["ctr"]
				var half: float = k["half"]
				var rng: float = k["range"]
				L.arc(p, rng, ctr - half, ctr + half, 16, ac, 2.2)
				L.seg(p, p + Vector2(cos(ctr - half), sin(ctr - half)) * rng, ac, 1.6)
				L.seg(p, p + Vector2(cos(ctr + half), sin(ctr + half)) * rng, ac, 1.6)
	# Grapples: lines across the rails and a pulsing ring round both ships.
	for s in sim.n_units:
		var o: int = sim.s_grap[s]
		if o > s or (o >= 0 and sim.s_grap[o] != s):
			var a: Vector2 = host._draw_pos(s)
			var b: Vector2 = host._draw_pos(o)
			for k in 4:
				var off := Vector2(sin(k * 2.1), cos(k * 1.3)) * 7.0
				L.seg(a + off, b - off, SeaKey.col("grapple", Color.WHITE, 0.95), 2.0)
			var mid := (a + b) * 0.5
			var rad := a.distance_to(b) * 0.5 + float(ST.stat(sim.s_type[s], "len")) * vis * 0.55
			L.arc(mid, rad + 2.0 * sin(_clock * 5.0), 0, TAU, 36, SeaKey.col("board", Color.WHITE, 0.85), 3.4)
	# A faint wind arrow on the water when the rose is not on the screen.
	var rose: Control = host._rose
	wind_arrow_shown = rose == null or not rose.is_visible_in_tree() or not Rect2(Vector2.ZERO, vp_size()).encloses(rose.get_global_rect())
	if wind_arrow_shown:
		var wa: float = (sim.w_from + 512) * TAU / 1024.0
		var wd := Vector2(cos(wa), sin(wa))
		var ctr2 := target + (world_at(vp_size() * Vector2(0.5, 0.78)) - target)
		var len_m := L.mpp * 70.0
		var tip := ctr2 + wd * len_m
		var wc := SeaKey.col("wind", Color.WHITE, 0.3)
		L.seg(ctr2 - wd * len_m, tip, wc, 3.0)
		var sd := Vector2(-wd.y, wd.x)
		L.seg(tip, tip - wd * len_m * 0.3 + sd * len_m * 0.22, wc, 3.0)
		L.seg(tip, tip - wd * len_m * 0.3 - sd * len_m * 0.22, wc, 3.0)
	L.commit()


## One ship's broadside arcs: [{ctr (radians), half (radians), range (m), loaded}] for the port and starboard guns.
func broadside_arcs(s: int) -> Array:
	var sim = host.sim
	var out: Array = []
	var h: int = sim.heading(s)
	for k in 2:
		var ctr := ((h - 256) if k == 0 else (h + 256)) * TAU / 1024.0
		out.append({"ctr": ctr, "half": SeaSim.ARC * TAU / 1024.0, "range": float(sim.shot_range(s, sim.s_ld[s * 2 + k])),
			"loaded": sim.s_rl[s * 2 + k] == 0})
	return out
