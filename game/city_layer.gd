extends Node2D
## A settlement on the battle map (view only), drawn from the generator's
## layout in sim.map_info["city"] (metres, final frame): buildings as flat
## roofs with a slight shadow, the wall as a thick stone strip with its
## walkway and battlements, round towers, the plaza. All static, drawn once
## (Godot keeps the draw list until the next queue_redraw, and batches it).
## The gates are a small child node redrawn each tick (open / closed /
## broken, a flash when hit); ground shading of streets, plaza and fields is
## in the terrain shader. Gate hit points and the plaza capture ring are in
## game/overlay.gd (drawn above the soldiers).

const MapGen := preload("res://sim/mapgen.gd")
const BattleSim := preload("res://sim/battle_sim.gd")

var sim
var px_per_m := 10.0
var lay: Dictionary = {}
var build_ms := 0.0
var gates_node: Node2D

const STONE := Color(0.46, 0.43, 0.39)
const STONE_DARK := Color(0.28, 0.26, 0.24)
const WALK := Color(0.62, 0.59, 0.53)
const SHADOW := Color(0, 0, 0, 0.3)
const ROOF := {MapGen.B_HOUSE: Color(0.66, 0.37, 0.26), MapGen.B_TEMPLE: Color(0.86, 0.83, 0.76),
	MapGen.B_MARKET: Color(0.78, 0.72, 0.6), MapGen.B_BARRACKS: Color(0.52, 0.32, 0.24),
	MapGen.B_STABLES: Color(0.55, 0.45, 0.32), MapGen.B_WORKSHOP: Color(0.46, 0.43, 0.39),
	MapGen.B_RANGE: Color(0.62, 0.5, 0.34)}
const THATCH := Color(0.66, 0.58, 0.4)


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
	var k := px_per_m
	# Plaza: a border and a fountain in the middle.
	var pl: Array = lay["plaza"]
	var hs: float = pl[2]
	var pr := Rect2(p(pl[0] - hs, pl[1] - hs), Vector2(hs, hs) * 2.0 * k)
	draw_rect(pr, Color(0.95, 0.92, 0.82, 0.18))
	draw_rect(pr, Color(0.3, 0.27, 0.22, 0.55), false, maxf(k * 0.35, 1.0))
	draw_circle(p(pl[0], pl[1]), k * 2.2, Color(0.55, 0.52, 0.47))
	draw_circle(p(pl[0], pl[1]), k * 1.6, Color(0.42, 0.58, 0.68))
	# Buildings: shadow, roof (gabled: a lighter and a darker half), ridge.
	var level: int = lay["level"]
	var sh_off := Vector2(0.9, 1.1) * k
	for b in lay["buildings"]:
		var r := Rect2(p(b[0], b[1]), Vector2(int(b[2]) - int(b[0]), int(b[3]) - int(b[1])) * k)
		draw_rect(Rect2(r.position + sh_off, r.size), SHADOW)
	for b in lay["buildings"]:
		var kind: int = b[4]
		var r := Rect2(p(b[0], b[1]), Vector2(int(b[2]) - int(b[0]), int(b[3]) - int(b[1])) * k)
		var h := (int(b[0]) * 73 + int(b[1]) * 151) % 100
		var col: Color = ROOF.get(kind, ROOF[MapGen.B_HOUSE])
		if kind == MapGen.B_HOUSE:
			if level == 0:
				col = THATCH
			col = col.lerp(Color(0.75, 0.5, 0.36) if h < 50 else Color(0.55, 0.32, 0.24), (h % 50) / 100.0)
		var horiz := r.size.x >= r.size.y
		draw_rect(r, col.darkened(0.12))
		var half := Rect2(r.position, Vector2(r.size.x, r.size.y * 0.5)) if horiz else Rect2(r.position, Vector2(r.size.x * 0.5, r.size.y))
		draw_rect(half, col.lightened(0.08))
		var a := r.position + (Vector2(0, r.size.y * 0.5) if horiz else Vector2(r.size.x * 0.5, 0))
		var b2 := a + (Vector2(r.size.x, 0) if horiz else Vector2(0, r.size.y))
		draw_line(a, b2, col.darkened(0.35), maxf(k * 0.25, 1.0))
		draw_rect(r, col.darkened(0.45), false, maxf(k * 0.15, 1.0))
		if kind == MapGen.B_TEMPLE or kind == MapGen.B_MARKET:
			# Colonnade: dots round the edge.
			var step := 2.0 * k
			var x := r.position.x + step * 0.5
			while x < r.end.x:
				draw_circle(Vector2(x, r.position.y + k * 0.6), k * 0.35, Color(0.95, 0.94, 0.9))
				draw_circle(Vector2(x, r.end.y - k * 0.6), k * 0.35, Color(0.95, 0.94, 0.9))
				x += step
	# The wall: stone band, walkway, battlements on the outer face.
	if int(lay["walls"]) > 0:
		_draw_wall()


func _draw_wall() -> void:
	var k := px_per_m
	var poly: PackedInt32Array = lay["poly"]
	var nv := poly.size() / 2
	var t: float = lay["t"]
	var pp: float = lay["pp"]
	var inner: float = lay["inner"]
	var off: float = (inner - pp) * 0.5
	var c := Vector2(lay["cx"], lay["cy"])
	for e in nv:
		var a := Vector2(poly[e * 2], poly[e * 2 + 1])
		var b := Vector2(poly[((e + 1) % nv) * 2], poly[((e + 1) % nv) * 2 + 1])
		var d := (b - a).normalized()
		var n := Vector2(-d.y, d.x)
		if n.dot((a + b) * 0.5 - c) < 0.0:
			n = -n
		# Shadow on the outside, then the body.
		_quad(a, b, n, t * 0.5 + 0.2, t * 0.5 + 1.6, Color(0, 0, 0, 0.28))
		_quad(a, b, n, -t * 0.5, t * 0.5, STONE)
		_quad(a, b, n, t * 0.5 - pp, t * 0.5, STONE_DARK)
		_quad(a, b, n, off - MapGen.WALK_W * 0.5, off + MapGen.WALK_W * 0.5, WALK)
		# Battlements: merlons along the outer edge every 2 m.
		var l := (b - a).length()
		var s := 1.0
		while s < l - 0.5:
			var m := a + d * s + n * (t * 0.5 - pp * 0.5)
			draw_rect(Rect2((m - Vector2(0.45, 0.45)) * k, Vector2(0.9, 0.9) * k), STONE.lightened(0.15))
			s += 2.0
	for tw in lay["towers"]:
		var tc := p(tw[0], tw[1])
		var r: float = float(tw[2]) * k
		draw_circle(tc + Vector2(1.2, 1.5) * k, r, Color(0, 0, 0, 0.3))
		draw_circle(tc, r, STONE_DARK)
		draw_circle(tc, r * 0.82, STONE.lightened(0.05))
		draw_circle(tc, r * 0.45, WALK)


## A band along edge a-b between offsets o0 and o1 (metres) along n.
func _quad(a: Vector2, b: Vector2, n: Vector2, o0: float, o1: float, col: Color) -> void:
	var k := px_per_m
	draw_colored_polygon(PackedVector2Array([(a + n * o0) * k, (b + n * o0) * k, (b + n * o1) * k,
		(a + n * o1) * k]), col)


## The gates, redrawn every tick: closed (timber and iron), open (the two
## leaves swung in), broken (splinters and rubble in the passage); a flash
## when one is struck.
class _Gates extends Node2D:
	var layer

	func _draw() -> void:
		var sim = layer.sim
		var k: float = layer.px_per_m
		var t: float = layer.lay["t"]
		var hw := float(MapGen.GATE_HW)
		for g in sim.n_gates:
			var gd: Dictionary = layer.lay["gates"][g]
			var ang: float = int(gd["dir"]) * TAU / 1024.0
			var n := Vector2(cos(ang), sin(ang))
			var e := Vector2(-n.y, n.x)
			var c := Vector2(gd["x"], gd["y"])
			var st: int = sim.g_state[g]
			var pts := PackedVector2Array([(c - e * hw - n * t * 0.5) * k, (c + e * hw - n * t * 0.5) * k,
				(c + e * hw + n * t * 0.5) * k, (c - e * hw + n * t * 0.5) * k])
			draw_colored_polygon(pts, Color(0.52, 0.48, 0.42))  # passage floor
			if st == BattleSim.GATE_CLOSED:
				var door := PackedVector2Array([(c - e * hw - n * 0.9) * k, (c + e * hw - n * 0.9) * k,
					(c + e * hw + n * 0.9) * k, (c - e * hw + n * 0.9) * k])
				draw_colored_polygon(door, Color(0.36, 0.22, 0.12))
				for q in range(-3, 4):
					var a := c + e * (q * hw / 4.0)
					draw_line((a - n * 0.9) * k, (a + n * 0.9) * k, Color(0.22, 0.13, 0.07), maxf(k * 0.12, 1.0))
				for q2 in [-0.5, 0.5]:
					draw_line((c - e * hw + n * q2) * k, (c + e * hw + n * q2) * k, Color(0.15, 0.15, 0.15), maxf(k * 0.2, 1.0))
			elif st == BattleSim.GATE_OPEN:
				# Leaves swung inward against the passage sides.
				for s in [-1.0, 1.0]:
					var hinge: Vector2 = c + e * hw * s - n * 0.6
					draw_line(hinge * k, (hinge - n * hw * 0.9) * k, Color(0.36, 0.22, 0.12), k * 0.6)
			else:
				# Broken: splinters and rubble, the same for both peers.
				for q in 14:
					var hx := float((g * 37 + q * 53) % 17) / 17.0 * 2.0 - 1.0
					var hy := float((g * 11 + q * 29) % 13) / 13.0 * 2.0 - 1.0
					var at: Vector2 = c + e * hx * hw * 0.9 + n * hy * (t * 0.5 + 2.0)
					var col := Color(0.36, 0.22, 0.12) if q % 3 != 0 else Color(0.5, 0.48, 0.44)
					var sz := (0.5 + float(q % 4) * 0.25) * k
					draw_rect(Rect2(at * k - Vector2(sz, sz * 0.5), Vector2(sz * 2.0, sz)), col)
			if sim.tick - sim.g_hit_t[g] < 4:
				draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]]),
					Color(1.0, 0.65, 0.2, 0.9), maxf(k * 0.4, 1.5))
