extends RefCounted
## The brass ruler (tabletop pass 5, docs/design/art_pipeline.md "Pass 5, furniture and motion"; view only): the deployment
## line and the range rings of a selected unit drawn as a thin band of warm brass lying on the board, with engraved ticks
## every 10 m (a longer one and a small number every 50 m), a bevel highlight along the upper-left edge (the lamp), a dark
## lower edge and a soft contact shadow to the lower right. The overlay's node draws through the lift shader, so the band is
## cut into pieces of at most SEG_M metres here and follows the hills; nothing here touches the sim.

const SEG_M := 8.0
const TICK_M := 10.0
const NUM_M := 50.0
const BRASS := Color(0.94, 0.65, 0.17)
const BRASS_HI := Color(1.0, 0.92, 0.58)
const BRASS_LO := Color(0.28, 0.16, 0.04)
const ENGRAVE := Color(0.22, 0.13, 0.03)
const PEWTER := Color(0.62, 0.64, 0.66)        # a ring whose men have no ammunition left: the same rule in grey metal
const PEWTER_LO := Color(0.22, 0.24, 0.27)


## The band's width in world px: 0.8 m, never under 4 screen px.
static func width_px(ppm: float, zoom: float) -> float:
	return maxf(0.8 * ppm, 5.0 / zoom)


## `pts` resampled so no piece is longer than SEG_M metres.
static func resample(pts: PackedVector2Array, ppm: float) -> PackedVector2Array:
	var seg := SEG_M * ppm
	var out := PackedVector2Array()
	for k in pts.size():
		if k > 0:
			var n := ceili(pts[k - 1].distance_to(pts[k]) / seg)
			for j in range(1, n):
				out.append(pts[k - 1].lerp(pts[k], float(j) / n))
		out.append(pts[k])
	return out


## The band itself: contact shadow, dark edge, brass body, bevel highlight. `alpha` fades the whole rule (a faint ring).
static func band(ci: CanvasItem, pts: PackedVector2Array, ppm: float, zoom: float, metal := true, alpha := 1.0) -> void:
	if pts.size() < 2:
		return
	var p := resample(pts, ppm)
	var w := width_px(ppm, zoom)
	var body := BRASS if metal else PEWTER
	var low := BRASS_LO if metal else PEWTER_LO
	var hi := BRASS_HI if metal else Color(0.9, 0.92, 0.95)
	var off := Vector2(0.28, 0.36) * w
	var sh := PackedVector2Array()
	sh.resize(p.size())
	for k in p.size():
		sh[k] = p[k] + off
	ci.draw_polyline(sh, Color(0, 0, 0, 0.12 * alpha), w * 2.4)
	ci.draw_polyline(sh, Color(0, 0, 0, 0.2 * alpha), w * 1.6)
	ci.draw_polyline(p, Color(low, 0.95 * alpha), w * 1.3)
	ci.draw_polyline(p, Color(body, alpha), w * 0.84)
	var hp := PackedVector2Array()
	hp.resize(p.size())
	for k in p.size():
		hp[k] = p[k] + Vector2(-0.2, -0.2) * w
	ci.draw_polyline(hp, Color(hi, 0.85 * alpha), w * 0.2)


## The ticks along `pts` (an open run of the rule, its first point the zero): every TICK_M metres of length, from the
## band's outer edge inward (towards `center`), a longer one with a number every NUM_M. `label(pos, text, size_px, col)` draws
## the number (the overlay's upright label). Ticks closer than 5 screen px are left out, the numbers need 26.
static func ticks(ci: CanvasItem, pts: PackedVector2Array, center: Vector2, ppm: float, zoom: float, label: Callable,
		alpha := 1.0, numbers_on := true) -> void:
	var step := TICK_M * ppm
	var every := 1
	while step * every * zoom < 5.0 and every < 64:
		every *= 2
	var w := width_px(ppm, zoom)
	var lw := maxf(1.6 / zoom, 0.05 * ppm)
	var acc := 0.0       # length walked
	var next := 0.0      # the next tick's length
	var tk := 0
	var numbers := numbers_on and step * 5.0 * zoom >= 26.0
	for k in range(1, pts.size()):
		var a := pts[k - 1]
		var b := pts[k]
		var d := a.distance_to(b)
		if d < 0.001:
			continue
		var t := (b - a) / d
		while next <= acc + d + 0.001:
			var p := a + t * clampf(next - acc, 0.0, d)
			var n := Vector2(-t.y, t.x)
			if n.dot(center - p) < 0.0:
				n = -n
			var five := tk % 5 == 0
			var l := w * (0.78 if five else 0.5)
			ci.draw_line(p - n * w * 0.4, p - n * w * 0.4 + n * l, Color(ENGRAVE, 0.85 * alpha), lw)
			if five and numbers and label.is_valid() and tk > 0:
				var txt := str(int(round(next / ppm)))
				label.call(p + n * (w * 0.5 + 6.0 / zoom), txt, maxf(5.0, 10.0 / zoom), Color(BRASS_HI, 0.95 * alpha))
			tk += every
			next = float(tk) * step
		acc += d
