extends RefCounted
## Rome's galleys in 3D (stage D2 part 4; docs/design/sea.md "The sea battle in 3D, stage D2"): the oar banks (one MultiMesh of thin
## boxes a galley, sweeping with the stroke as the 2D screen's `_draw_galley`: the rate 5.0 at ramming speed, 2.8 under way, a phase
## step of 0.55 an oar along the bank; still when resting or struck, held out level), the corvus (a post and a plank at the bow,
## raised and stowed upright, dropped across onto the grappled enemy, hauled up after CORVUS_COOL) and a ram blow's splinters.
## The bronze ram is part of the model (tools/battlekit/export_ships.py). View only: reads the sim.

const SeaShip := preload("res://game/sea_ship3d.gd")
const ST := preload("res://sim/sea_types.gd")
const SeaSimS := preload("res://sim/sea_sim.gd")

const PAIRS := {"lembos": 5, "trireme": 8, "quinquereme": 9, "quinquereme_p": 9}
const OAR_COL := Color(0.30, 0.20, 0.11)
const BLADE_COL := Color(0.52, 0.38, 0.2)
const PLANK_COL := Color(0.84, 0.78, 0.6)


static func pairs(ty: int) -> int:
	return int(PAIRS.get(SeaShip.model_key(ty), 0))


## The oar's mesh: a shaft one metre long along local +z from the pivot and a blade at its end (scaled along z by the reach).
static func oar_mesh() -> ArrayMesh:
	var b := SeaShip.Buf.new()
	b.box(Vector3(0, 0, 0.5), 0.12, 0.12, 1.0, OAR_COL)
	b.box(Vector3(0, -0.02, 0.93), 0.42, 0.05, 0.16, BLADE_COL)
	return b.mesh()


## Where oar k of the bank sits in the ship's frame on the starboard side (x, y, z), at the model's scale `vis`.
static func port(ty: int, vis: float, k: int) -> Vector3:
	var d := SeaShip.dims(ty, vis)
	var ln: float = d["ln"]
	var bm: float = d["bm"]
	var fb: float = d["fb"]
	var n := pairs(ty)
	var u := 0.18 + 0.58 * (float(k) + 0.5) / maxf(float(n), 1.0)
	var tab := [[0.0, 0.55], [0.06, 0.82], [0.2, 1.0], [0.62, 1.0], [0.82, 0.8], [0.94, 0.42], [1.0, 0.04]]
	var hb := 0.04
	for i in tab.size() - 1:
		if u >= float(tab[i][0]) and u <= float(tab[i + 1][0]):
			hb = lerpf(float(tab[i][1]), float(tab[i + 1][1]), (u - float(tab[i][0])) / (float(tab[i + 1][0]) - float(tab[i][0])))
	return Vector3((u - 0.5) * ln, fb * 0.67, hb * bm * 0.5 + 0.8 * vis / 2.0 * 1.0)


## The oar rate (radians a second) of the 2D screen's rule: 5.0 at ramming speed, 2.8 under way, 0 resting or struck.
static func rate(sim, s: int) -> float:
	if sim.u_state[s] == SeaSimS.S_SAIL and sim.s_spd[s] > 50:
		return 5.0 if sim.s_sail[s] == 2 else 2.8
	return 0.0


## Oar k's transform on side si (0 starboard, 1 port) in the ship's frame at oar rate `rt` and clock `t`.
static func oar_transform(ty: int, vis: float, rt: float, t: float, k: int, si: int) -> Transform3D:
	var bm: float = SeaShip.dims(ty, vis)["bm"]
	var reach := bm * 1.05
	var p := port(ty, vis, k)
	var phase := t * rt + float(k) * 0.55
	var sw := sin(phase) * 0.32 if rt > 0.0 else 0.0
	var pd := (0.62 - 0.25 * maxf(0.0, cos(phase))) if rt > 0.0 else 0.35   # the blade bites on the pull, lifts on the recovery
	var sg := 1.0 if si == 0 else -1.0
	var dir := Vector3(sin(sw * 1.2 - 0.3) * cos(pd), -sin(pd), sg * cos(sw * 1.2 - 0.3) * cos(pd)).normalized()
	var xax := Vector3(0, 1, 0).cross(dir).normalized()
	var yax := dir.cross(xax).normalized()
	return Transform3D(Basis(xax, yax, dir * reach), Vector3(p.x, p.y, p.z * sg))


## One frame of a galley's oars into `mm` (2 x pairs instances) at clock `t`.
static func sweep(mm: MultiMesh, ty: int, vis: float, rt: float, t: float) -> void:
	for k in pairs(ty):
		for si in 2:
			mm.set_instance_transform(k * 2 + si, oar_transform(ty, vis, rt, t, k, si))


## The corvus: a post and its plank in the ship's frame, `drop` 0 (stowed upright, a little forward) .. 1 (laid across toward
## `yaw` radians from the bow, the direction of the grappled ship in the ship's frame).
static func corvus_mesh(ty: int, vis: float, drop: float, yaw: float) -> ArrayMesh:
	var d := SeaShip.dims(ty, vis)
	var ln: float = d["ln"]
	var bm: float = d["bm"]
	var fb: float = d["fb"]
	var b := SeaShip.Buf.new()
	var px := ln * 0.30
	var post_top := fb + bm * 0.9
	b.bar(Vector3(px, fb - 0.2, 0), Vector3(px, post_top, 0), maxf(0.5, bm * 0.07), SeaShip.COL_MAST)
	var plen := bm * 1.15
	# stowed: the plank hauled up, tip forward and high; dropped: the plank swung round toward the target and down onto its rail.
	var up_dir := Vector3(0.45, 0.89, 0).normalized()
	var down_dir := Vector3(cos(yaw) * 0.97, -0.24, sin(yaw) * 0.97).normalized()
	var dirv := up_dir.slerp(down_dir, clampf(drop, 0.0, 1.0)).normalized()
	var base := Vector3(px, post_top - 0.4, 0)
	var tip := base + dirv * plen
	b.bar(base, tip, maxf(0.7, bm * 0.13), PLANK_COL)
	b.bar(tip - dirv * 0.4, tip + dirv * 0.5 + Vector3(0, -0.5 * drop, 0), maxf(0.3, bm * 0.05), Color(0.14, 0.12, 0.1))   # the iron spike
	return b.mesh()
