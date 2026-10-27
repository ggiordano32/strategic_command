extends RefCounted
const BattleSim := preload("res://sim/battle_sim.gd")
## The last-seen ghost (view only, 2026-10-27; docs/design/ui.md "The last-seen
## ghost"): an enemy unit that was drawn and is hidden from the viewer's side
## now (BattleSim.hidden_from, line of sight) is remembered here at the place
## and facing it had when it dropped out of sight, so the overlay can draw it
## greyed and fading instead of letting it vanish. Reads the sim, never writes
## it; no hash, no lockstep input. Each viewer keeps its own (its own side).

const GHOST_FADE := 4.0   # seconds the men and the marker fade to the faint outline

## unit -> {"x","y" (centroid), "ax","ay" (formation front), "face", "files",
## "alive", "side", "t0" (wall-clock ms it dropped out of sight), "mx","my" (the
## men's positions, empty on Low)}. Present only while the unit is a ghost.
var recs := {}
var _shown := PackedByteArray()   # unit -> drawn (not hidden) at the last update


## Once a frame. `now_ms` is wall-clock (Time.get_ticks_msec); `with_men`
## copies the men's positions (off on Graphics Low).
func update(sim, side: int, now_ms: int, with_men: bool) -> void:
	if side < 0 or sim == null:
		return
	var n: int = sim.n_units
	if _shown.size() != n:
		_shown.resize(n)
		_shown.fill(0)
		recs.clear()
	if sim.winner >= 0:
		recs.clear()
		return
	for u in n:
		if sim.u_side[u] == side:
			continue
		if sim.u_state[u] >= BattleSim.U_DESTROYED or sim.u_alive[u] <= 0:
			_shown[u] = 0
			recs.erase(u)
			continue
		if sim.hidden_from(u, side):
			if _shown[u] != 0 and not recs.has(u):
				recs[u] = _record(sim, u, now_ms, with_men)
			_shown[u] = 0
		else:
			_shown[u] = 1
			recs.erase(u)   # seen again, anywhere: the ghost clears at once


func _record(sim, u: int, now_ms: int, with_men: bool) -> Dictionary:
	var mx := PackedInt32Array()
	var my := PackedInt32Array()
	if with_men:
		var base: int = sim.u_slot_base[u]
		for s in sim.u_alive[u]:
			var i: int = sim.slot_soldier[base + s]
			mx.append(sim.pos_x[i])
			my.append(sim.pos_y[i])
	return {"x": sim.u_cx[u], "y": sim.u_cy[u], "ax": sim.u_ax[u], "ay": sim.u_ay[u],
		"face": sim.u_face[u], "files": sim.u_files[u], "alive": sim.u_alive[u],
		"side": sim.u_side[u], "t0": now_ms, "mx": mx, "my": my}


## 0 at the moment it dropped out of sight, 1 from GHOST_FADE on (the outline stage).
func fade(rec: Dictionary, now_ms: int) -> float:
	return clampf((now_ms - int(rec["t0"])) / (GHOST_FADE * 1000.0), 0.0, 1.0)


## True while any ghost still has its men or marker fading (a redraw is due).
func animating(now_ms: int) -> bool:
	for u in recs:
		if fade(recs[u], now_ms) < 1.0:
			return true
	return false
