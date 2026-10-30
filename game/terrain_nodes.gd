extends RefCounted
## The ground's height nodes in metres at a 2 m spacing (the sim's 4 m heights cubic-interpolated once along x and once
## along y). One copy for the terrain shader's height texture (terrain_layer.gd) and the oblique view's lift field
## (board_view.gd), cached per sim so a battle builds it once. View only.

const NODE_M := 2.0
static var _sim = null
static var nx := 2
static var ny := 2
static var heights := PackedFloat32Array()


static func build(sim) -> PackedFloat32Array:
	if _sim == sim and not heights.is_empty():
		return heights
	_sim = sim
	var snx: int = sim.ter_nx
	var sny: int = sim.ter_ny
	var src := PackedFloat32Array()
	src.resize(snx * sny)
	for k in snx * sny:
		src[k] = sim.ter_h[k] / 1024.0
	nx = snx * 2 - 1
	ny = sny * 2 - 1
	var rows := PackedFloat32Array()
	rows.resize(nx * sny)
	for j in sny:
		var o := j * snx
		var r := j * nx
		for i in snx:
			rows[r + 2 * i] = src[o + i]
			if i < snx - 1:
				var a := src[o + maxi(i - 1, 0)]
				var b := src[o + i]
				var c := src[o + i + 1]
				var d := src[o + mini(i + 2, snx - 1)]
				rows[r + 2 * i + 1] = (-a + 9.0 * b + 9.0 * c - d) / 16.0
	heights = PackedFloat32Array()
	heights.resize(nx * ny)
	for i in nx:
		for j in sny:
			heights[(2 * j) * nx + i] = rows[j * nx + i]
			if j < sny - 1:
				var a := rows[maxi(j - 1, 0) * nx + i]
				var b := rows[j * nx + i]
				var c := rows[(j + 1) * nx + i]
				var d := rows[mini(j + 2, sny - 1) * nx + i]
				heights[(2 * j + 1) * nx + i] = (-a + 9.0 * b + 9.0 * c - d) / 16.0
	return heights


## The commonest height (0.1 m bins) of `h`, the terrain shader's `h_base_m` before its `- lo` (terrain_layer `_commonest`).
static func commonest(h: PackedFloat32Array, lo: float) -> float:
	var hist := {}
	var best := 0
	var best_n := 0
	for v in h:
		var b := int(floor((v - lo) * 10.0))
		var c: int = hist.get(b, 0) + 1
		hist[b] = c
		if c > best_n or (c == best_n and b < best):
			best = b
			best_n = c
	return lo + (best + 0.5) / 10.0
