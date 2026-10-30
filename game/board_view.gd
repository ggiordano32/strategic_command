extends RefCounted
## The battle view's board transform (tabletop pass 3, docs/design/art_pipeline.md "Pass 3, the oblique view").
## A view preference in user://settings.cfg [video] battle_view = top | oblique ("--battle-view=top|oblique" overrides
## it for the session; default oblique since 2026-10-30, the owner's call). On the web a battle whose oblique sheets
## are not mounted (game/oblique_pack.gd: the download cancelled or failed) is drawn in the top view (`web_top`). View only: it reads the sim's heights once per battle and never writes the sim.
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

## The view of the battle being set up (set by `begin`; tests set `force` first).
static var oblique := false
static var force := ""               # tests: "top" / "oblique" (overrides the setting and the command line)
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


static func pref() -> String:
	if force == "top" or force == "oblique":
		return force
	for a in OS.get_cmdline_user_args():
		if str(a).begins_with("--battle-view="):
			var v := str(a).get_slice("=", 1).to_lower()
			if v == "top" or v == "oblique":
				return v
	if OS.has_feature("web"):
		var q = JavaScriptBridge.eval("window.location.search", true)
		if q is String and (q as String).contains("battle-view=oblique"):
			return "oblique"
	var cf := ConfigFile.new()
	if cf.load(SETTINGS) != OK:
		return "oblique"
	return "top" if str(cf.get_value("video", "battle_view", "oblique")) == "top" else "oblique"


static func save_pref(v: String) -> void:
	var cf := ConfigFile.new()
	cf.load(SETTINGS)
	cf.set_value("video", "battle_view", v)
	cf.save(SETTINGS)


## Set up the view for a new battle on `sim` (before the layers are built).
static func begin(sim, p_px_per_m: float) -> void:
	oblique = pref() == "oblique" and not web_top
	px_per_m = p_px_per_m
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
	base_m = 0.0
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
			var v := (hm[k] - base_m) * px_per_m * OBLIQUE_SIN
			lift[k] = v
			lift_max = maxf(lift_max, v)
			lift_min = minf(lift_min, v)
	_uni = PackedVector4Array()
	_uni.resize(GRID_VEC4)
	for q in GRID_VEC4:
		var v4 := Vector4()
		for c in 4:
			var k := q * 4 + c
			v4[c] = lift[k] if k < lift.size() else 0.0
		_uni[q] = v4


## Sets the view's uniforms (game/board_view.gdshaderinc) on a material whose shader includes it.
static func apply(mat: ShaderMaterial) -> void:
	mat.set_shader_parameter("ob_on", 1.0 if oblique else 0.0)
	mat.set_shader_parameter("ob_geo", Vector4(cell_px, float(nx), float(ny), 0.0))
	mat.set_shader_parameter("ob_field", field_px)
	mat.set_shader_parameter("ob_lift", _uni)
	mat.set_shader_parameter("ob_lrange", Vector2(lift_max, lift_min))


## The lift (board px) at world point w, and its derivative along y (per world px).
static func lift_dy(w: Vector2) -> Vector2:
	if not oblique:
		return Vector2.ZERO
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


static func lift_px(w: Vector2) -> float:
	return lift_dy(w).x


## World point (px) at ground level (plus h_m metres above it) -> board point (px).
static func to_board(w: Vector2, h_m := 0.0) -> Vector2:
	if not oblique:
		return w
	return Vector2(w.x, w.y * OBLIQUE_COS - lift_px(w) - h_m * px_per_m * OBLIQUE_SIN)


## Board point (px) -> the ground point under it (world px): the ground plane at h = 0, then refined by the lift.
static func to_world(b: Vector2, iters := 3) -> Vector2:
	if not oblique:
		return b
	var y := b.y / OBLIQUE_COS
	for it in iters:
		var l := lift_dy(Vector2(b.x, y))
		var f := y * OBLIQUE_COS - l.x - b.y
		var d := maxf(OBLIQUE_COS - l.y, 0.2 * OBLIQUE_COS)
		y -= f / d
	return Vector2(b.x, y)


## The board rect the field covers (with its lift).
static func board_field() -> Rect2:
	if not oblique:
		return Rect2(Vector2.ZERO, field_px)
	return Rect2(0.0, -lift_max, field_px.x, field_px.y * OBLIQUE_COS + lift_max - lift_min)


## The world rect seen through a board rect (for culling): every ground point whose board point may fall in it.
static func world_rect(br: Rect2) -> Rect2:
	if not oblique:
		return br
	var y0 := (br.position.y + lift_min) / OBLIQUE_COS
	var y1 := (br.end.y + lift_max) / OBLIQUE_COS
	return Rect2(br.position.x, y0, br.size.x, y1 - y0)


## Nearness along the view of ground point w (world px) h_m metres up: what is nearer draws over what is farther.
static func near_px(w: Vector2, h_m := 0.0) -> float:
	var lm := lift_px(w) / OBLIQUE_SIN + h_m * px_per_m   # height above the base, world px
	return w.y * OBLIQUE_SIN + lm * OBLIQUE_COS


## The draw transform that makes the lift shader draw the next items upright at `anchor` (world px; see UP_K).
static func up_xf(anchor: Vector2) -> Transform2D:
	if not oblique:
		return Transform2D.IDENTITY
	return Transform2D(Vector2(1.0, 0.0), Vector2(0.0, UP_K), anchor * (1.0 - UP_K))


## A plain lift material (game/board_lift.gdshader) for a draw-based layer: its ground drawing is squashed and lifted,
## items under up_xf are drawn upright. Also widens the node's cull rect (its drawing moves on screen).
static func lift_node(ci: CanvasItem) -> void:
	if not oblique or ci == null:
		return
	var mat := ShaderMaterial.new()
	mat.shader = load("res://game/board_lift.gdshader")
	apply(mat)
	ci.material = mat
	cull_wide(ci)


## The node's own drawing is placed by its shader: never cull it by its world rect.
static func cull_wide(ci: CanvasItem) -> void:
	if not oblique or ci == null:
		return
	var pad := 4000.0
	RenderingServer.canvas_item_set_custom_rect(ci.get_canvas_item(), true,
		Rect2(-pad, -pad - lift_max, field_px.x + 2.0 * pad, field_px.y + 2.0 * pad + lift_max))
