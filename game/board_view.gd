extends RefCounted
## The battle view's board transform (tabletop pass 3, docs/design/art_pipeline.md "Pass 3, the oblique view").
## The view is 3D for every player (stage B, 2026-11-09); "--battle-view=top|oblique" is a hidden developer aid until stage C
## removes the flat views (an old [video] battle_view setting is ignored). On the web a battle whose oblique sheets
## are missing (a broken build; they ship in the main pack) would be drawn in the top view (`web_top`, never set now). View only: it reads the sim's heights once per battle and never writes the sim.
##
## Top: the board is the world (world pixels, the map seen from straight above), as before.
## Oblique: the table seen from the south, the camera 40 degrees above the horizon (50 degrees from the vertical, the
## tilt), orthographic. A ground point (x, y) at height h (world pixels, metres) goes to the board point
##     (x, y * OBLIQUE_COS - lift(x, y))       lift = (h - base) * px_per_m * OBLIQUE_SIN
## with OBLIQUE_COS = cos(tilt) = sin(elevation) and OBLIQUE_SIN = sin(tilt) = cos(elevation); the camera's zoom and pan
## apply after this (the Camera2D works in board pixels). Heights come from one coarse lift grid (at most GRID_MAX x
## GRID_MAX nodes over the field, each the mean of the sim's heights round it, the map's commonest height as 0) that
## every layer shares: the ground shader inverts it per pixel, the figures, trays, overlay and kit are placed by it, so
## all of them meet the ground exactly. Taps go back through `to_world`: the board point to the ground plane at h = 0,
## then refined by the lift under it (Newton steps; the lift is bilinear, so a step inside one cell is exact).
##
## Pass 6 (the hills, docs/design/art_pipeline.md): every lift is scaled by HEIGHT_EXAG (the oblique view only), and on the
## texture path the coarse grid gives way to a fine lift field (2 m nodes, a half-float texture read in the vertex stage:
## `fine`), quantised into the terrain's foam bands with a short ramp so each riser is a vertical face; the coarse grid stays
## for the CPU-fed soldier path, Graphics Low and `--lift-grid`. The inverse then marches along the view ray.
##
## The 3D view (2026-11-06, docs/design/art_pipeline.md "The 3D battle view, step one"; `[video] battle_view = 3d`): the battle is a
## Node3D scene (game/view3d.gd) under an orthographic Camera3D that turns freely in yaw and tilts (`set_view`); `oblique` is true
## as well, and the board transform above is the same one generalised: a ground point w goes to
##     (dot(w, r), dot(w, f) * C - lift(w) * lift_k)
## with r / f the camera's right / toward-the-viewer directions on the ground, C = sin(elevation) and lift_k = cos(elevation) /
## OBLIQUE_SIN (the lifts are kept at the oblique view's 40 degrees). With yaw 0 at 40 degrees it is the oblique view's exactly. The
## overlay and the taps keep using this transform; the 3D camera is placed from the Camera2D so the two agree pixel for pixel.
##
## Shaders read the same grid (game/board_view.gdshaderinc, `apply` sets the uniforms). The figures' nearness (what
## draws over what) is NEAR(y, h) = y * OBLIQUE_SIN + h * OBLIQUE_COS (world pixels along the view).

const SETTINGS := "user://settings.cfg"
const ELEVATION_DEG := 40.0
const OBLIQUE_COS := 0.6427876097   # cos(50 deg): ground y on the board (sin of the 40 degree elevation)
const OBLIQUE_SIN := 0.7660444431   # sin(50 deg): heights on the board (cos of the elevation)
const GRID_MAX := 29                # lift nodes a side at most (29 x 29 = 841 floats: 211 vec4 uniforms)
const GRID_VEC4 := 211
const MIN_CELL_M := 20.0
## The upright mark (game/board_lift.gdshader): a draw transform scale(1, UP_K) with origin anchor * (1 - UP_K) tells
## the lift shader to draw the following items upright (screen-aligned, unsquashed) at the anchor's board point.
const UP_K := 0.999
## Vertical exaggeration of every lift in the oblique view (pass 6; the top view is unchanged). `--height-exag=` overrides it.
const HEIGHT_EXAG := 1.4
const FINE_M := 2.0                 # the fine lift field's node spacing (metres); 4 m past FINE_MAX_NODES nodes a side
const FINE_MAX_NODES := 1100
const BAND_M := 2.0                 # the terrain's contour / foam band (terrain.gdshader minor_m)
const RAMP := 0.18                  # the riser's share of a band (height), a smoothstep ramp: the vertical face
const TerrainNodes := preload("res://game/terrain_nodes.gd")

## The view of the battle being set up (set by `begin`; tests set `force` first).
static var oblique := false
static var force := ""               # tests: "top" / "oblique" / "3d" (overrides the setting and the command line)
## The 3D view (see above): its camera's yaw (radians, 0 looking north) and elevation, set by game/view3d.gd through `set_view`.
static var v3d := false
static var yaw := 0.0
static var elev_deg := ELEVATION_DEG
static var ob_c := OBLIQUE_COS       # sin(elevation): ground depth on the board
static var ob_s := OBLIQUE_SIN       # cos(elevation): heights on the board
static var lift_k := 1.0             # ob_s / OBLIQUE_SIN: the stored lifts (at 40 degrees) to this elevation
static var dir_r := Vector2(1.0, 0.0)   # the camera's right on the ground (world, unit)
static var dir_f := Vector2(0.0, 1.0)   # toward the viewer on the ground (screen down; world, unit)
static var web_top := false          # set by the battle: the web without the oblique sheets draws this battle from the top
static var px_per_m := 10.0
static var field_px := Vector2(1000.0, 1000.0)
static var cell_px := 200.0
static var nx := 2
static var ny := 2
static var lift := PackedFloat32Array()    # board px per node
static var lift_max := 0.0
static var lift_min := 0.0
static var base_m := 0.0
static var _uni := PackedVector4Array()
static var exag := HEIGHT_EXAG
static var vtf_off := false          # the 3D view runs on the compatible path (no vertex texture reads): the footprints' stamp cannot run, so they are off
static var fine := false             # the fine lift field is in use (else the coarse grid)
static var fine_nx := 2
static var fine_ny := 2
static var fine_cell_px := 20.0
static var fine_l := PackedFloat32Array()  # smooth lift (board px) per fine node
static var fine_tex: Texture2D
static var fine_max := 0.0           # the quantised field's highest / lowest lift (the active mode's range is lrange)
static var fine_min := 0.0
static var steps := false            # the fine field is quantised into foam bands (diorama)
static var q_band := 1.0             # a band's height in lift px
static var q_off := 0.0              # lv = lift / q_band + q_off: band 0 starts at the terrain's commonest height
static var crest_ghost := false
static var grid_max := 0.0           # the coarse grid's own lift range (board px)
static var grid_min := 0.0
static var _mats: Array = []         # weak refs of every material `apply` was called on (use_grid re-applies them)


## The battle view every player gets is "3d" (stage B, 2026-11-09): a saved [video] battle_view of top or oblique (an old
## settings file) reads as 3d and nothing in the Options sets another. Hidden developer aid until stage C deletes the flat views:
## `--battle-view=top|oblique` on the command line and the tests' `force`. The web query parameter honours 3d only.
static func pref() -> String:
	if force == "top" or force == "oblique" or force == "3d":
		return force
	for a in OS.get_cmdline_user_args():
		if str(a).begins_with("--battle-view="):
			var v := str(a).get_slice("=", 1).to_lower()
			if v == "top" or v == "oblique" or v == "3d":
				return v
	return "3d"


## Testing aids: "--height-exag=1.4", "--lift-grid" (the coarse grid everywhere), "--no-steps" (the fine field smooth),
## "--crest-ghost=on|off" (a flag only).
static func _arg(prefix: String, default := "") -> String:
	for a in OS.get_cmdline_user_args():
		if str(a).begins_with(prefix):
			return str(a).get_slice("=", 1)
	return default


## (the flat views' crest ghost is a developer aid now: the command-line flag only, no setting)
static func crest_ghost_pref() -> bool:
	var v := _arg("--crest-ghost=")
	return v == "on" or v == "1" or v == "true"


## Set up the view for a new battle on `sim` (before the layers are built).
static func begin(sim, p_px_per_m: float) -> void:
	var pv := pref()
	oblique = (pv == "oblique" or pv == "3d") and not web_top
	v3d = pv == "3d" and not web_top
	set_view(0.0, ELEVATION_DEG)
	vtf_off = false
	if v3d:
		var sl = load("res://game/soldier_layer.gd")
		var fp: String = sl.forced_path()
		vtf_off = fp == "cpu" or (fp == "" and sl.load_pref() == "cpu")
	px_per_m = p_px_per_m
	exag = HEIGHT_EXAG
	var ex := _arg("--height-exag=")
	if ex != "":
		exag = clampf(float(ex), 0.5, 4.0)
	_mats.clear()
	field_px = Vector2(sim.field_w, sim.field_h) / 1024.0 * px_per_m
	var fw_m: float = sim.field_w / 1024.0
	var fh_m: float = sim.field_h / 1024.0
	var cm := maxf(MIN_CELL_M, ceilf(maxf(fw_m, fh_m) / float(GRID_MAX - 1)))
	nx = clampi(int(ceilf(fw_m / cm)) + 1, 2, GRID_MAX)
	ny = clampi(int(ceilf(fh_m / cm)) + 1, 2, GRID_MAX)
	cell_px = cm * px_per_m
	lift = PackedFloat32Array()
	lift.resize(nx * ny)
	lift.fill(0.0)
	lift_max = 0.0
	lift_min = 0.0
	grid_max = 0.0
	grid_min = 0.0
	base_m = 0.0
	fine = false
	steps = false
	fine_max = 0.0
	fine_min = 0.0
	fine_tex = null
	crest_ghost = oblique and crest_ghost_pref()
	var k_lift := px_per_m * OBLIQUE_SIN * exag
	if oblique and sim.ter_on != 0:
		# Each node: the mean of 5 x 5 samples over its cell (a smooth lift), then the commonest height (1 m bins) as 0.
		var hm := PackedFloat32Array()
		hm.resize(nx * ny)
		var hist := {}
		for j in ny:
			for i in nx:
				var acc := 0.0
				for sj in 5:
					for si in 5:
						var x := (float(i) + (si - 2) * 0.2) * cm
						var y := (float(j) + (sj - 2) * 0.2) * cm
						acc += sim.height_at(int(clampf(x, 0.0, fw_m) * 1024.0), int(clampf(y, 0.0, fh_m) * 1024.0)) / 1024.0
				var h := acc / 25.0
				hm[j * nx + i] = h
				var b := int(floor(h))
				hist[b] = int(hist.get(b, 0)) + 1
		var best := 0
		var best_n := -1
		for j in ny:
			for i in nx:
				var b := int(floor(hm[j * nx + i]))
				if int(hist[b]) > best_n or (int(hist[b]) == best_n and b < best):
					best = b
					best_n = int(hist[b])
		base_m = best + 0.5
		for k in nx * ny:
			var v := (hm[k] - base_m) * k_lift
			lift[k] = v
			lift_max = maxf(lift_max, v)
			lift_min = minf(lift_min, v)
		grid_max = lift_max
		grid_min = lift_min
		_build_fine(sim, k_lift)
	_uni = PackedVector4Array()
	_uni.resize(GRID_VEC4)
	for q in GRID_VEC4:
		var v4 := Vector4()
		for c in 4:
			var k := q * 4 + c
			v4[c] = lift[k] if k < lift.size() else 0.0
		_uni[q] = v4


## The fine lift field: the terrain's 2 m height nodes (4 m past FINE_MAX_NODES a side), a half-float texture, quantised
## into the terrain's foam bands in the shaders and `lift_px` when `steps` (the diorama look). The coarse grid's range is
## kept in lift_max / lift_min as well: the union is what rects and culls use, so a fall-back to the grid needs no resize.
static func _build_fine(sim, k_lift: float) -> void:
	# (loaded at run time: quality.gd and soldier_layer.gd preload this file)
	var Quality = load("res://game/quality.gd")
	var BattleLook = load("res://game/battle_look.gd")
	if "--lift-grid" in OS.get_cmdline_user_args() or Quality.is_low():
		return
	var sl = load("res://game/soldier_layer.gd")
	var forced: String = sl.forced_path()
	if forced == "cpu" or (forced == "" and sl.load_pref() == "cpu"):
		return
	var hn := TerrainNodes.build(sim)
	var tnx := TerrainNodes.nx
	var tny := TerrainNodes.ny
	var st := 1 if maxi(tnx, tny) <= FINE_MAX_NODES else 2
	fine_nx = (tnx - 1) / st + 1
	fine_ny = (tny - 1) / st + 1
	fine_cell_px = FINE_M * st * px_per_m
	fine_l = PackedFloat32Array()
	fine_l.resize(fine_nx * fine_ny)
	var lo := hn[0]
	for v in hn:
		lo = minf(lo, v)
	var hb := TerrainNodes.commonest(hn, lo)   # the terrain's commonest height, the foam bands' origin
	steps = BattleLook.is_diorama() and "--no-steps" not in OS.get_cmdline_user_args()
	q_band = BAND_M * px_per_m * OBLIQUE_SIN * exag
	q_off = (base_m - hb) / BAND_M
	for j in fine_ny:
		for i in fine_nx:
			fine_l[j * fine_nx + i] = (hn[(j * st) * tnx + i * st] - base_m) * k_lift
	var mx := -1e9
	var mn := 1e9
	for v in fine_l:
		mx = maxf(mx, v)
		mn = minf(mn, v)
	fine_max = _quant(mx)
	fine_min = _quant(mn)
	var img := Image.create_from_data(fine_nx, fine_ny, false, Image.FORMAT_RF, fine_l.to_byte_array())
	img.convert(Image.FORMAT_RH)
	fine_tex = ImageTexture.create_from_image(img)
	fine = true
	if "--lift-stats" in OS.get_cmdline_user_args():
		print("LIFT fine %d x %d nodes (%.0f m), lift %.1f .. %.1f px (quantised %.1f .. %.1f), steps=%s exag=%.2f field %.0f x %.0f m" % [
			fine_nx, fine_ny, fine_cell_px / px_per_m, mn, mx, fine_min, fine_max, str(steps), exag, field_px.x / px_per_m, field_px.y / px_per_m])
	lift_max = maxf(lift_max, maxf(fine_max, mx))
	lift_min = minf(lift_min, minf(fine_min, mn))


## The foam steps on a stored lift (board px at 40 degrees): the 3D view's board mesh (game/view3d.gd).
static func quant(l: float) -> float:
	return _quant(l)


## The foam steps: lift (board px) snapped to the terrain's bands, each riser a ramp RAMP of a band high (terrain.gdshader's
## ob_quant is the same function).
static func _quant(l: float) -> float:
	if not steps:
		return l
	var lv := l / q_band + q_off
	var n := floorf(lv + 0.5)
	var u := lv + 0.5 - n
	var t := clampf(u / RAMP, 0.0, 1.0)
	return (n - 1.0 + t * t * (3.0 - 2.0 * t) - q_off) * q_band


## Drop to the coarse grid for the rest of the battle (the CPU-fed soldier path was chosen at run time: it cannot read
## the field), and re-apply every material that was given the field.
static func use_grid() -> void:
	if not fine:
		return
	fine = false
	steps = false
	for r in _mats:
		var m = r.get_ref()
		if m != null:
			apply(m, false)


## Sets the view's uniforms (game/board_view.gdshaderinc) on a material whose shader includes it.
static func apply(mat: ShaderMaterial, register := true) -> void:
	if register:
		_mats.append(weakref(mat))
	mat.set_shader_parameter("ob_on", 1.0 if oblique else 0.0)
	mat.set_shader_parameter("ob_geo", Vector4(cell_px, float(nx), float(ny), 0.0))
	mat.set_shader_parameter("ob_field", field_px)
	mat.set_shader_parameter("ob_lift", _uni)
	if fine:
		mat.set_shader_parameter("ob_lrange", Vector2(fine_max, fine_min))
		mat.set_shader_parameter("ob_fine", 1.0)
		mat.set_shader_parameter("ob_fgeo", Vector4(fine_cell_px, float(fine_nx), float(fine_ny), 0.0))
		mat.set_shader_parameter("ob_fq", Vector4(q_band if steps else 0.0, 1.0 / q_band, q_off, RAMP))
		mat.set_shader_parameter("ob_ftex", fine_tex)
	else:
		mat.set_shader_parameter("ob_lrange", Vector2(grid_max, grid_min))
		mat.set_shader_parameter("ob_fine", 0.0)
	if v3d:
		_apply_view(mat)


## The 3D view's camera terms (game/board_view.gdshaderinc under V3D).
static func _apply_view(mat: ShaderMaterial) -> void:
	mat.set_shader_parameter("ob_r", dir_r)
	mat.set_shader_parameter("ob_f", dir_f)
	mat.set_shader_parameter("ob_cs", Vector2(ob_c, ob_s))
	mat.set_shader_parameter("ob_lk", lift_k)


## The 3D view: the camera's yaw (radians: 0 looks north, positive turns the view clockwise seen from above) and elevation
## (degrees above the horizon). Re-applies the terms to every registered material. The oblique view is (0, 40).
static func set_view(p_yaw: float, p_elev_deg: float) -> void:
	yaw = p_yaw
	elev_deg = p_elev_deg
	if not v3d:
		yaw = 0.0
		elev_deg = ELEVATION_DEG
		ob_c = OBLIQUE_COS
		ob_s = OBLIQUE_SIN
		lift_k = 1.0
		dir_r = Vector2(1.0, 0.0)
		dir_f = Vector2(0.0, 1.0)
		return
	var e := deg_to_rad(elev_deg)
	ob_c = sin(e)
	ob_s = cos(e)
	lift_k = ob_s / OBLIQUE_SIN
	dir_r = Vector2(cos(yaw), -sin(yaw))
	dir_f = Vector2(sin(yaw), cos(yaw))
	for r in _mats:
		var m = r.get_ref()
		if m != null:
			_apply_view(m)


## A ground direction (world px) -> its direction on the board (the transform's linear part, no lift).
static func dir_board(d: Vector2) -> Vector2:
	if not oblique:
		return d
	if v3d:
		return Vector2(d.dot(dir_r), d.dot(dir_f) * ob_c)
	return Vector2(d.x, d.y * OBLIQUE_COS)


## The coarse grid's lift (board px) at world point w, and its derivative along y (per world px).
static func lift_dy(w: Vector2) -> Vector2:
	var g := w.clamp(Vector2.ZERO, field_px) / cell_px
	var i0 := clampi(int(floor(g.x)), 0, nx - 2)
	var j0 := clampi(int(floor(g.y)), 0, ny - 2)
	var fx := clampf(g.x - i0, 0.0, 1.0)
	var fy := clampf(g.y - j0, 0.0, 1.0)
	var k := j0 * nx + i0
	var top := lerpf(lift[k], lift[k + 1], fx)
	var bot := lerpf(lift[k + nx], lift[k + nx + 1], fx)
	var d := (bot - top) / cell_px if w.y > 0.0 and w.y < field_px.y else 0.0
	return Vector2(lerpf(top, bot, fy), d)


## The smooth fine lift (board px) at world point w: bilinear over the fine nodes (the texture's own filter).
static func _fine_smooth(w: Vector2) -> float:
	var g := w.clamp(Vector2.ZERO, field_px) / fine_cell_px
	var i0 := clampi(int(floor(g.x)), 0, fine_nx - 2)
	var j0 := clampi(int(floor(g.y)), 0, fine_ny - 2)
	var fx := clampf(g.x - i0, 0.0, 1.0)
	var fy := clampf(g.y - j0, 0.0, 1.0)
	var k := j0 * fine_nx + i0
	return lerpf(lerpf(fine_l[k], fine_l[k + 1], fx), lerpf(fine_l[k + fine_nx], fine_l[k + fine_nx + 1], fx), fy)


static func lift_px(w: Vector2) -> float:
	if not oblique:
		return 0.0
	if fine:
		return _quant(_fine_smooth(w)) * lift_k
	return lift_dy(w).x * lift_k


## A board direction (px) -> the ground direction (world px) under it (the inverse of dir_board).
static func dir_world(d: Vector2) -> Vector2:
	if not oblique:
		return d
	if v3d:
		return dir_r * d.x + dir_f * (d.y / ob_c)
	return Vector2(d.x, d.y / OBLIQUE_COS)


## The ground's height in metres above the base at world point w (the 3D view's y, the exaggeration included).
static func ground_m(w: Vector2) -> float:
	if not oblique:
		return 0.0
	var l := _quant(_fine_smooth(w)) if fine else lift_dy(w).x
	return l / (px_per_m * OBLIQUE_SIN)


## World point (px) at ground level (plus h_m metres above it) -> board point (px).
static func to_board(w: Vector2, h_m := 0.0) -> Vector2:
	if not oblique:
		return w
	if v3d:
		return Vector2(w.dot(dir_r), w.dot(dir_f) * ob_c - lift_px(w) - h_m * px_per_m * ob_s)
	return Vector2(w.x, w.y * OBLIQUE_COS - lift_px(w) - h_m * px_per_m * OBLIQUE_SIN)


## Board point (px) -> the ground point under it (world px). The coarse grid: the ground plane at h = 0 refined by Newton
## steps (the lift is linear along y inside a cell). The fine field: the nearest root of y x COS - lift(x, y) = b along the
## view ray, marched from the near end in 1/32 of the lift's range and bisected (the steps' risers are ramps, so the
## function is continuous).
static func to_world(b: Vector2, iters := 3) -> Vector2:
	if not oblique:
		return b
	if v3d:
		return _to_world_3d(b)
	if fine:
		var y_hi := (b.y + lift_max) / OBLIQUE_COS
		var y_lo := (b.y + lift_min) / OBLIQUE_COS
		var n := 48
		var step := (y_hi - y_lo) / float(n)
		var ya := y_hi
		var yb := y_lo
		for i in range(1, n + 1):
			var yy := y_hi - step * i
			if yy * OBLIQUE_COS - lift_px(Vector2(b.x, yy)) - b.y <= 0.0:
				yb = yy
				break
			ya = yy
		for it in 24:
			var ym := 0.5 * (ya + yb)
			if ym * OBLIQUE_COS - lift_px(Vector2(b.x, ym)) - b.y > 0.0:
				ya = ym
			else:
				yb = ym
		return Vector2(b.x, 0.5 * (ya + yb))
	var y := b.y / OBLIQUE_COS
	for it in iters:
		var l := lift_dy(Vector2(b.x, y))
		var f := y * OBLIQUE_COS - l.x - b.y
		var d := maxf(OBLIQUE_COS - l.y, 0.2 * OBLIQUE_COS)
		y -= f / d
	return Vector2(b.x, y)


## The 3D view's inverse: along the view ray through board point b (u = b.x fixed, v the ground depth toward the viewer), the
## nearest root of v x C - lift(r u + f v) = b.y, marched from the near end in 1/48 of the lift's range and bisected.
static func _to_world_3d(b: Vector2) -> Vector2:
	var lmax := maxf(lift_max, 0.0) * lift_k
	var lmin := minf(lift_min, 0.0) * lift_k
	var v_hi := (b.y + lmax) / ob_c
	var v_lo := (b.y + lmin) / ob_c
	var base := dir_r * b.x
	if v_hi - v_lo < 0.01:
		return base + dir_f * v_hi
	var n := 48
	var step := (v_hi - v_lo) / float(n)
	var va := v_hi
	var vb := v_lo
	for i in range(1, n + 1):
		var vv := v_hi - step * i
		if vv * ob_c - lift_px(base + dir_f * vv) - b.y <= 0.0:
			vb = vv
			break
		va = vv
	for it in 24:
		var vm := 0.5 * (va + vb)
		if vm * ob_c - lift_px(base + dir_f * vm) - b.y > 0.0:
			va = vm
		else:
			vb = vm
	return base + dir_f * (0.5 * (va + vb))


## The board rect the field covers (with its lift).
static func board_field() -> Rect2:
	if not oblique:
		return Rect2(Vector2.ZERO, field_px)
	if v3d:
		var r := Rect2(to_board(Vector2.ZERO), Vector2.ZERO)
		for c in [Vector2(field_px.x, 0.0), Vector2(0.0, field_px.y), field_px]:
			r = r.expand(Vector2((c as Vector2).dot(dir_r), (c as Vector2).dot(dir_f) * ob_c))
		r = r.expand(Vector2.ZERO)
		r.position.y -= maxf(lift_max, 0.0) * lift_k
		r.size.y += (maxf(lift_max, 0.0) - minf(lift_min, 0.0)) * lift_k
		return r
	return Rect2(0.0, -lift_max, field_px.x, field_px.y * OBLIQUE_COS + lift_max - lift_min)


## The world rect seen through a board rect (for culling): every ground point whose board point may fall in it.
static func world_rect(br: Rect2) -> Rect2:
	if not oblique:
		return br
	if v3d:
		var r := Rect2(to_world(br.position), Vector2.ZERO)
		for c in [Vector2(br.end.x, br.position.y), Vector2(br.position.x, br.end.y), br.end]:
			r = r.expand(to_world(c))
		return r.grow(maxf(lift_max - lift_min, 0.0) * lift_k / ob_c)
	var y0 := (br.position.y + lift_min) / OBLIQUE_COS
	var y1 := (br.end.y + lift_max) / OBLIQUE_COS
	return Rect2(br.position.x, y0, br.size.x, y1 - y0)


## Nearness along the view of ground point w (world px) h_m metres up: what is nearer draws over what is farther.
static func near_px(w: Vector2, h_m := 0.0) -> float:
	if v3d:
		return w.dot(dir_f) * ob_s + (lift_px(w) / ob_s + h_m * px_per_m) * ob_c
	var lm := lift_px(w) / OBLIQUE_SIN + h_m * px_per_m   # height above the base, world px
	return w.y * OBLIQUE_SIN + lm * OBLIQUE_COS


## The draw transform that makes the lift shader draw the next items upright at `anchor` (world px; see UP_K).
static func up_xf(anchor: Vector2) -> Transform2D:
	if not oblique:
		return Transform2D.IDENTITY
	return Transform2D(Vector2(1.0, 0.0), Vector2(0.0, UP_K), anchor * (1.0 - UP_K))


## A plain lift material (game/board_lift.gdshader) for a draw-based layer: its ground drawing is squashed and lifted,
## items under up_xf are drawn upright. Also widens the node's cull rect (its drawing moves on screen).
## `draped`: the node's long straight pieces (a cliff's brow, a track, a field's edge) follow the smooth lift, not the foam steps
## (their vertices are far apart, so a step between two of them would tear the drawing); short marks stay on the steps.
static func lift_node(ci: CanvasItem, draped := false) -> void:
	if not oblique or ci == null:
		return
	var mat := ShaderMaterial.new()
	mat.shader = load("res://game/board_lift3d.gdshader" if v3d else "res://game/board_lift.gdshader")
	apply(mat)
	if draped and fine and steps:
		mat.set_shader_parameter("ob_fq", Vector4(0.0, 1.0 / q_band, q_off, RAMP))
	ci.material = mat
	cull_wide(ci)


## The node's own drawing is placed by its shader: never cull it by its world rect.
static func cull_wide(ci: CanvasItem) -> void:
	if not oblique or ci == null:
		return
	var pad := 4000.0
	RenderingServer.canvas_item_set_custom_rect(ci.get_canvas_item(), true,
		Rect2(-pad, -pad - lift_max, field_px.x + 2.0 * pad, field_px.y + 2.0 * pad + lift_max))
