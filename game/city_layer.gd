extends Node2D
## A settlement on the battle map (view only), drawn from the generator's
## layout in sim.map_info["city"] (metres, final frame) by game/city_draw.gd:
## roofs by building culture, the owner's shrine, walls, towers, the
## citadel, stairs, the harbour, banners. All static, drawn once (Godot
## keeps the draw list until the next queue_redraw, and batches it). The
## gates are a small child node redrawn each tick (open / closed / broken,
## a flash when hit); ground shading of streets, plaza, fields, the sea and
## the ditch is in the terrain shader. Gate hit points and the capture ring
## are in game/overlay.gd (drawn above the soldiers).

const CityDraw := preload("res://game/city_draw.gd")
const BattleKit := preload("res://game/battlekit.gd")
const CityStreets := preload("res://game/city_streets.gd")
const MapGen := preload("res://sim/mapgen.gd")
const Quality := preload("res://game/quality.gd")

var sim
var px_per_m := 10.0
var lay: Dictionary = {}
var build_ms := 0.0
var gates_node: Node2D
var kit: Node2D                # walls, towers, gates from the battle kit (null: the old drawing)
var over_node: Node2D          # stairs and banners above the kit
var use_kit := true
var bridge: Dictionary = {}   # a river crossing's bridge (sim.map_info["river"], kind 1)


func setup(p_sim, p_px_per_m: float) -> void:
	sim = p_sim
	px_per_m = p_px_per_m
	if sim.riv_on != 0 and sim.map_info.has("river") and int(sim.map_info["river"]["kind"]) == 1:
		bridge = sim.map_info["river"]
		queue_redraw()
	if sim.city_on == 0 or not sim.map_info.has("city"):
		return
	lay = sim.map_info["city"]
	if "--city-info" in OS.get_cmdline_user_args():
		print("CITY cx=%s cy=%s t=%s pp=%s inner=%s walls=%s plan=%s pal=%s ntow=%d ngate=%d nseg=%d nv=%d cit=%s tow0=%s gate0=%s" % [lay["cx"], lay["cy"], lay["t"], lay["pp"], lay["inner"], lay["walls"], lay.get("plan"), lay["palisade"], lay["towers"].size(), lay["gates"].size(), lay["segs"].size(), lay["poly"].size() / 2, not lay["cit"].is_empty(), lay["towers"][0] if lay["towers"].size() > 0 else 0, lay["gates"][0] if lay["gates"].size() > 0 else 0])
	var t0 := Time.get_ticks_usec()
	use_kit = not ("--no-kit" in OS.get_cmdline_user_args())
	if use_kit:
		var st := Sprite2D.new()
		st.set_script(CityStreets)
		add_child(st)
		var sty := clampi(int(lay.get("founder", lay.get("plan", 0))), 0, 7)
		for a in OS.get_cmdline_user_args():
			if str(a).begins_with("--kit-culture="):
				sty = clampi(int(str(a).get_slice("=", 1)), 0, 7)
		st.build(lay, px_per_m, sty, sim)
		kit = BattleKit.new()
		add_child(kit)
		kit.setup(sim, lay, px_per_m)
		over_node = _Over.new()
		over_node.layer = self
		add_child(over_node)
		over_node.queue_redraw()
	gates_node = _Gates.new()
	gates_node.layer = self
	add_child(gates_node)
	queue_redraw()
	build_ms = (Time.get_ticks_usec() - t0) / 1000.0


# ---------------------------------------------------------------- paths ---
# The Paths overlay (view only): a faint red diagonal hatch on every cell the
# sim says men cannot stand in on the ground (BattleSim.nav's ground bit:
# houses, walls, rocks, cliffs; the sea is left clear), a sparser amber one
# the other way on rubble (a breach, a fallen house: slow going, low cover), one mask texture of the
# map's 2 m cells built once on first use, hatched by a shader in world
# space, faded by its alpha (game/battle.gd: 2 s after the selection changes).

const SETTINGS := "user://settings.cfg"
const PATHS_SHADER := """
shader_type canvas_item;
uniform float alpha = 0.0;
uniform float period = 10.0;
varying vec2 wpos;
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy; }
void fragment() {
	float m = texture(TEXTURE, UV).r;
	float h = fract((wpos.x + wpos.y) / period);
	float d = abs(h - 0.5) * 2.0;
	float w = max(fwidth(d), 0.02);
	float line = smoothstep(0.62 - w, 0.62 + w, d);
	if (m > 0.75) {
		COLOR = vec4(0.95, 0.30, 0.22, (0.10 + 0.55 * line) * alpha);
	} else {
		// rubble (mask 0.5): slow going, low cover - a sparser amber hatch the other way
		float h2 = fract((wpos.x - wpos.y) / (period * 1.6));
		float d2 = abs(h2 - 0.5) * 2.0;
		float w2 = max(fwidth(d2), 0.02);
		float l2 = smoothstep(0.75 - w2, 0.75 + w2, d2);
		COLOR = vec4(0.98, 0.72, 0.25, step(0.25, m) * (0.06 + 0.5 * l2) * alpha);
	}
}
"""
var paths_node: Sprite2D
var paths_cells := 0          # cells hatched (tests)
var paths_alpha := 0.0
var _paths_rub := 0           # sim.rub_n the mask was built for (destruction: rebuilt when rubble appears)


static func load_paths_pref() -> bool:
	var cf := ConfigFile.new()
	return cf.load(SETTINGS) != OK or int(cf.get_value("ui", "paths", 1)) != 0


static func save_paths_pref(on: bool) -> void:
	var cf := ConfigFile.new()
	cf.load(SETTINGS)
	cf.set_value("ui", "paths", 1 if on else 0)
	cf.save(SETTINGS)


## Cells the hatch covers: the ground bit is clear and it is not the sea.
func paths_mask() -> PackedByteArray:
	var n: int = sim.ob_w * sim.ob_h
	var px := PackedByteArray()
	px.resize(n)
	var cnt := 0
	for i in n:
		if (sim.nav[i] & MapGen.NAV_GROUND) == 0 and sim.obs[i] != MapGen.C_WATER:
			px[i] = 255
			cnt += 1
		elif sim.obs[i] == MapGen.C_RUBBLE:
			px[i] = 128  # (rubble: walkable, slow; a sparse yellow hatch)
	_paths_rub = sim.rub_n
	paths_cells = cnt
	return px


## Set the hatch's strength (0 hides it); builds the mask on first use.
func set_paths_alpha(a: float) -> void:
	paths_alpha = a
	if a <= 0.001:
		if paths_node != null:
			paths_node.visible = false
		return
	if sim == null or sim.obs_on == 0 or sim.city_on == 0:
		return
	if paths_node != null and _paths_rub != sim.rub_n:
		paths_node.texture = ImageTexture.create_from_image(Image.create_from_data(sim.ob_w, sim.ob_h, false,
			Image.FORMAT_R8, paths_mask()))
	if paths_node == null:
		var img := Image.create_from_data(sim.ob_w, sim.ob_h, false, Image.FORMAT_R8, paths_mask())
		paths_node = Sprite2D.new()
		paths_node.texture = ImageTexture.create_from_image(img)
		paths_node.centered = false
		paths_node.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		paths_node.scale = Vector2.ONE * (2.0 * px_per_m)
		var mat := ShaderMaterial.new()
		var sh := Shader.new()
		sh.code = PATHS_SHADER
		mat.shader = sh
		mat.set_shader_parameter("period", px_per_m * 0.9)
		paths_node.material = mat
		add_child(paths_node)
	paths_node.visible = true
	(paths_node.material as ShaderMaterial).set_shader_parameter("alpha", a)


## Redraw the gates (after a tick).
func refresh() -> void:
	if kit != null:
		kit.refresh()
	if gates_node != null:
		gates_node.queue_redraw()


func p(x: float, y: float) -> Vector2:
	return Vector2(x, y) * px_per_m


func _draw() -> void:
	if not bridge.is_empty():
		draw_bridge(self, bridge, px_per_m, Vector2.ZERO)
	if lay.is_empty():
		return
	CityDraw.draw_static(self, lay, px_per_m, Vector2.ZERO, true, false, use_kit)


## A river crossing's stone bridge (layout `r`: x0, x1, the two mouths, m):
## a deck from bank to bank with its parapets, cutwaters at the piers and
## its shadow on the water; scale `sc` px a metre, offset `o`.
static func draw_bridge(ci: CanvasItem, r: Dictionary, sc: float, o: Vector2) -> void:
	var x0 := float(int(r["x0"]))
	var x1 := float(int(r["x1"]))
	var ma: Array = r["mouth"][0]
	var mb: Array = r["mouth"][1]
	var ya := minf(float(int(ma[1])), float(int(mb[1]))) + 2.0
	var yb := maxf(float(int(ma[1])), float(int(mb[1]))) - 2.0
	var pt := func(x: float, y: float) -> Vector2: return o + Vector2(x, y) * sc
	# Shadow on the water (light from the upper left), then the deck.
	ci.draw_rect(Rect2(pt.call(x0 + 0.8, ya + 0.8), Vector2(x1 - x0, yb - ya) * sc), Color(0.05, 0.08, 0.1, 0.35))
	# Cutwaters: a pointed pier nose every ~9 m either side of the deck.
	var span := yb - ya
	var piers := maxi(int(span / 9.0), 1)
	for k in range(1, piers + 1):
		var y := ya + span * k / (piers + 1)
		for side in [-1.0, 1.0]:
			var ex: float = x0 if side < 0.0 else x1
			ci.draw_colored_polygon(PackedVector2Array([pt.call(ex, y - 1.2), pt.call(ex + side * 1.8, y),
				pt.call(ex, y + 1.2)]), Color(0.52, 0.49, 0.44))
	ci.draw_rect(Rect2(pt.call(x0, ya), Vector2(x1 - x0, span) * sc), Color(0.66, 0.62, 0.55))
	# Paving courses across the deck.
	var yy := ya + 1.2
	while yy < yb - 0.6:
		ci.draw_line(pt.call(x0 + 0.6, yy), pt.call(x1 - 0.6, yy), Color(0.55, 0.51, 0.45, 0.6), maxf(sc * 0.08, 1.0))
		yy += 1.2
	# Parapets.
	var pw := 0.6
	for ex2 in [x0, x1 - pw]:
		ci.draw_rect(Rect2(pt.call(ex2, ya - 0.4), Vector2(pw, span + 0.8) * sc), Color(0.47, 0.44, 0.39))
	# Abutments on the banks.
	for yv in [ya - 1.6, yb]:
		ci.draw_rect(Rect2(pt.call(x0 - 1.0, yv), Vector2(x1 - x0 + 2.0, 1.6) * sc), Color(0.56, 0.52, 0.46))


## The gates, redrawn every tick.
class _Gates extends Node2D:
	var layer
	var _rub_seen := 0
	var _rub_cells := PackedInt32Array()

	func _draw() -> void:
		var sim = layer.sim
		if not layer.use_kit and sim.rub_n > 0:
			# (The drawn style without the kit: the rubble of breaches and fallen houses here; the kit
			# draws its own, game/battlekit.gd.)
			if sim.rub_n != _rub_seen:
				_rub_seen = sim.rub_n
				_rub_cells = CityDraw.rubble_cells(sim)
			CityDraw.draw_rubble(self, sim, _rub_cells, layer.px_per_m, Vector2.ZERO, Quality.is_low())
		for g in sim.n_gates:
			CityDraw.draw_gate(self, layer.lay, g, sim.g_state[g], sim.tick - sim.g_hit_t[g] < 4, sim.tick,
				layer.px_per_m, Vector2.ZERO, layer.use_kit)


## Stairs and banners, above the kit's walls and towers.
class _Over extends Node2D:
	var layer

	func _draw() -> void:
		CityDraw.draw_over(self, layer.lay, layer.px_per_m, Vector2.ZERO)
