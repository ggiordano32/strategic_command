extends Node2D
## Field works on the battle map (docs/DESIGN.md "Field works and the
## fortified camp"): a camp's ditch (dark shading) and its rampart (an earth
## bank with a wooden palisade of posts and planks along its outer edge;
## burnt-down sections leave charred stumps), stakes lines (a row of short
## diagonal stakes leaning at the enemy) and caltrop fields (scattered dots,
## drawn only for a side that knows of them: its owner, or the enemy once
## its men have stepped in: BattleSim.works_known). Under the soldiers, so
## it is the same on the GPU and the CPU soldier paths. Each piece is drawn
## by its kind's fields (height, cover, charge stop, hidden), never by name.
## Redrawn only when a piece changes (placed, moved, turned, worn, found,
## burnt down). It never touches the sim.

const BattleSim := preload("res://sim/battle_sim.gd")
const M := 1024.0

var sim
var px_per_m := 10.0
var viewer_side := 0
var _sig := -1

const COL_DITCH := Color(0.20, 0.15, 0.09, 0.72)
const COL_DITCH_DEEP := Color(0.11, 0.08, 0.05, 0.75)
const COL_BANK := Color(0.52, 0.42, 0.27, 0.85)
const COL_WOOD := Color(0.42, 0.28, 0.13, 1.0)
const COL_WOOD_LIGHT := Color(0.62, 0.45, 0.24, 1.0)
const COL_CHAR := Color(0.12, 0.10, 0.08, 0.9)
const COL_IRON := Color(0.16, 0.16, 0.18, 0.95)


func setup(p_sim, p_px_per_m: float) -> void:
	sim = p_sim
	px_per_m = p_px_per_m
	_sig = -1
	refresh()


## Redraw if any piece changed since the last drawing (cheap: called every
## view tick and while deploying).
func refresh() -> void:
	if sim == null or sim.fw_on == 0:
		visible = false
		return
	visible = true
	var h := 17
	for q in sim.n_eq:
		if BattleSim.EQ_FW[sim.q_kind[q]] == 0:
			continue
		var hp0: int = maxi(BattleSim.EQ_HP[sim.q_kind[q]], 1)
		h = (h * 31 + sim.q_state[q] * 7 + sim.q_x[q] + sim.q_y[q] * 3 + sim.q_face[q] * 11
			+ sim.q_seen[q] * 13 + (sim.q_hp[q] * 8 / hp0) * 17 + viewer_side) & 0x3FFFFFFF
	if h != _sig:
		_sig = h
		queue_redraw()


func _draw() -> void:
	if sim == null or sim.fw_on == 0:
		return
	var lw := maxf(1.0, px_per_m * 0.12)
	# Ditches first, then banks, then the rest on top.
	for pass_n in 3:
		for q in sim.n_eq:
			var k: int = sim.q_kind[q]
			if BattleSim.EQ_FW[k] == 0:
				continue
			var st: int = sim.q_state[q]
			if st != BattleSim.Q_FIXED and st != BattleSim.Q_WRECKED:
				continue
			if not sim.works_known(q, viewer_side):
				continue
			var order := 0 if BattleSim.EQ_H[k] < 0 else (1 if BattleSim.EQ_COVER[k] > 0 else 2)
			if order != pass_n:
				continue
			draw_piece(self, sim, q, px_per_m, lw)


## Draw piece q on ci (world px); shared with the overlay's ghosts.
static func draw_piece(ci: CanvasItem, p_sim, q: int, ppm: float, lw: float, ghost: bool = false,
		at := Vector2.INF, face := -1) -> void:
	var k: int = p_sim.q_kind[q]
	var c: Vector2 = Vector2(p_sim.q_x[q], p_sim.q_y[q]) / M * ppm if at == Vector2.INF else at
	var ang: float = (p_sim.q_face[q] if face < 0 else face) * TAU / 1024.0
	var f := Vector2(cos(ang), sin(ang))   # toward the enemy
	var a := Vector2(-f.y, f.x)            # along the line
	var hl: float = p_sim.q_len[q] / M * ppm / 2.0
	var hd: float = BattleSim.EQ_FW_DEPTH[k] / M * ppm / 2.0
	var wrecked: bool = p_sim.q_state[q] == BattleSim.Q_WRECKED
	var alpha := 0.55 if ghost else 1.0
	var rect := PackedVector2Array([c - a * hl - f * hd, c + a * hl - f * hd, c + a * hl + f * hd, c - a * hl + f * hd])
	if BattleSim.EQ_H[k] < 0:
		# The ditch: dark shading, deepest along its middle.
		ci.draw_colored_polygon(rect, COL_DITCH)
		ci.draw_line(c - a * hl, c + a * hl, COL_DITCH_DEEP, hd)
		return
	if BattleSim.EQ_COVER[k] > 0:
		# The rampart: an earth bank, the palisade along its outer edge.
		ci.draw_colored_polygon(rect, Color(COL_BANK, COL_BANK.a * alpha))
		var edge := c + f * hd * 0.55
		var step := ppm * 0.55
		var n := maxi(int(hl * 2.0 / step), 1)
		if wrecked:
			for j in n + 1:
				if j % 3 == 0:
					ci.draw_circle(edge - a * hl + a * (j * step), lw * 0.9, COL_CHAR)
			return
		ci.draw_line(edge - a * hl - f * ppm * 0.25, edge + a * hl - f * ppm * 0.25, Color(COL_WOOD_LIGHT, alpha), lw * 1.2)
		for j in n + 1:
			var p := edge - a * hl + a * (j * step)
			ci.draw_line(p - f * ppm * 0.2, p + f * ppm * 0.25, Color(COL_WOOD, alpha), lw * 1.6)
		return
	if BattleSim.EQ_HIDE[k] != 0:
		# Caltrops: scattered dots (fewer as the stock is used up).
		var hp0: int = maxi(BattleSim.EQ_HP[k], 1)
		var dots: int = 48 if ghost else 48 * maxi(p_sim.q_hp[q], 0) / hp0
		ci.draw_rect(Rect2(c - Vector2(hd, hd), Vector2(hd, hd) * 2.0), Color(0.3, 0.3, 0.32, 0.18 * alpha), false, lw * 0.6)
		for j in dots:
			var hx := float(((q + 1) * 7919 + j * 104729) % 1000) / 1000.0 * 2.0 - 1.0
			var hy := float(((q + 1) * 15485863 + j * 32452843) % 1000) / 1000.0 * 2.0 - 1.0
			ci.draw_circle(c + a * (hx * hl) + f * (hy * hd), lw * 0.55, Color(COL_IRON, alpha))
		return
	# Stakes: a row of short stakes leaning at the enemy, two rows staggered.
	var col := COL_CHAR if wrecked else Color(COL_WOOD, alpha)
	var st2 := ppm * 0.8
	var m := maxi(int(hl * 2.0 / st2), 1)
	for j in m + 1:
		if wrecked and j % 4 != 0:
			continue
		for row in 2:
			var base := c - a * hl + a * (j * st2 + (st2 * 0.5 if row == 1 else 0.0)) - f * hd * (0.6 if row == 0 else 0.0)
			if (base - c).dot(a) > hl:
				continue
			var tip := base + f * ppm * (0.6 if wrecked else 1.3) + a * ppm * 0.3
			ci.draw_line(base, tip, col, lw * 1.1)
