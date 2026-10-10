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

var sim
var px_per_m := 10.0
var lay: Dictionary = {}
var build_ms := 0.0
var gates_node: Node2D
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
	var t0 := Time.get_ticks_usec()
	gates_node = _Gates.new()
	gates_node.layer = self
	add_child(gates_node)
	queue_redraw()
	build_ms = (Time.get_ticks_usec() - t0) / 1000.0


## Redraw the gates (after a tick).
func refresh() -> void:
	if gates_node != null:
		gates_node.queue_redraw()


func p(x: float, y: float) -> Vector2:
	return Vector2(x, y) * px_per_m


func _draw() -> void:
	if not bridge.is_empty():
		draw_bridge(self, bridge, px_per_m, Vector2.ZERO)
	if lay.is_empty():
		return
	CityDraw.draw_static(self, lay, px_per_m, Vector2.ZERO, true, false)


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

	func _draw() -> void:
		var sim = layer.sim
		for g in sim.n_gates:
			CityDraw.draw_gate(self, layer.lay, g, sim.g_state[g], sim.tick - sim.g_hit_t[g] < 4, sim.tick,
				layer.px_per_m, Vector2.ZERO)
