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


func setup(p_sim, p_px_per_m: float) -> void:
	sim = p_sim
	px_per_m = p_px_per_m
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
	if lay.is_empty():
		return
	CityDraw.draw_static(self, lay, px_per_m, Vector2.ZERO, true, false)


## The gates, redrawn every tick.
class _Gates extends Node2D:
	var layer

	func _draw() -> void:
		var sim = layer.sim
		for g in sim.n_gates:
			CityDraw.draw_gate(self, layer.lay, g, sim.g_state[g], sim.tick - sim.g_hit_t[g] < 4, sim.tick,
				layer.px_per_m, Vector2.ZERO)
