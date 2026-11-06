extends SceneTree
## Line of fire past buildings probe (docs/design/battle_sim.md "Buildings
## block a flat shot (as built, 2026-11-06)"): a 60-man shooting line (a
## musket line or a bow line) and a 40-man pike block standing behind a
## house (a 40 x 12 m field block), the pikes fully hidden behind it, half
## hidden (its middle at the house's corner) or beside it, the line 40 m or
## 120 m off (middle to middle). Modes: atk (an attack order on the pikes),
## faw (fire at will, standing), faw2 (fire at will with a second enemy
## block in the open 70 m to the side), ai (the shooters' side AI). Prints
## per case the shots, the pikes' and the decoy's losses, the line's
## blocked count, the flat shots stopped on the way, the shots drawn across
## the house (straight line from the man to the landing crossing a building
## cell), how far the line walked, the first shot's second, and the line
## of fire at the start (lof_units: the preview's "NO LINE OF FIRE").
##   godot --headless --script res://tests/lof_probe.gd [-- --secs=60 --only=musket]

const BattleSim := preload("res://sim/battle_sim.gd")
const FM := preload("res://sim/fixed_math.gd")
const Scenarios := preload("res://sim/scenarios.gd")
const UT := preload("res://sim/unit_types.gd")
const Terrain := preload("res://sim/terrain.gd")
const MapGen := preload("res://sim/mapgen.gd")
const M := 1024

const HOUSE := [180, 190, 220, 202]  # x0, y0, x1, y1 (m)
const TY := 210                      # the pikes' middle, 8 m behind the house


static var los := 1


static func scenario(weapon: String, pos: String, dist: int, mode: String) -> Dictionary:
	if pos == "town":
		return town(weapon, dist, mode)
	var tx := 200
	if pos == "half":
		tx = 220
	elif pos == "beside":
		tx = 250
	var sk := "musketeers" if weapon == "musket" else "archer"
	var sh := Scenarios.unit(0, UT.index_of(sk), 60, 200, TY - dist, Scenarios.FACE_DOWN, 20)
	var tg := Scenarios.unit(1, UT.index_of("w_pikemen"), 40, tx, TY, Scenarios.FACE_UP, 16)
	var units := [sh, tg]
	if mode == "faw2":
		units.append(Scenarios.unit(1, UT.index_of("w_pikemen"), 40, 200 - 70, TY, Scenarios.FACE_UP, 16))
	return {"width_m": 400, "height_m": 400, "ai_sides": [0] if mode == "ai" else [], "orders": [],
		"units": units, "time_limit": 600, "los": los,
		"terrain": {"kind": Terrain.K_FLAT, "blocks": [HOUSE], "urban": [[170, 180, 230, 215]]}}


## A West open town (cover_probe's wtown): the outermost house with open
## ground 120 m out from it; the pikes 8 m behind its inner face (toward the
## plaza), the line `dist` out from them through the house.
static func town(weapon: String, dist: int, mode: String) -> Dictionary:
	var city := {"seed": 12, "level": 1, "walls": 0, "bld": [1, 2, 4], "plan": MapGen.CUL_LATIN, "coast": 1,
		"founder": MapGen.CUL_LATIN, "west": 1}
	var terr := {"kind": Terrain.K_FLAT, "seed": 710, "forest": 0, "ground": MapGen.PAL_GREEN}
	var sk := "musketeers" if weapon == "musket" else "archer"
	var r := Scenarios.settlement(city, terr, [[UT.index_of(sk), 60]], [[UT.index_of("w_pikemen"), 40]], 1, [])
	var sc: Dictionary = r["scenario"]
	var lay: Dictionary = r["layout"]
	var pl: Array = lay["plaza"]
	var best := -1.0
	var pick := []
	for b in lay["buildings"]:
		var bb: Array = b
		var cx := (float(bb[0]) + float(bb[2])) * 0.5
		var cy := (float(bb[1]) + float(bb[3])) * 0.5
		var out := Vector2(cx - float(pl[0]), cy - float(pl[1]))
		var dd := out.length()
		if dd < 1.0 or absf(float(bb[2]) - float(bb[0])) < 10.0 or absf(float(bb[3]) - float(bb[1])) < 6.0:
			continue
		out /= dd
		var half := absf(out.x) * absf(float(bb[2]) - float(bb[0])) * 0.5 + absf(out.y) * absf(float(bb[3]) - float(bb[1])) * 0.5
		var tc := Vector2(cx, cy) - out * (half + 8.0)
		var sc2 := tc + out * 120.0
		if sc2.x < 20 or sc2.y < 20 or sc2.x > sc["width_m"] - 20 or sc2.y > sc["height_m"] - 20:
			continue
		if dd > best:
			best = dd
			pick = [tc, out]
	var t: Vector2 = pick[0]
	var o: Vector2 = pick[1]
	# (8 m past the house's inner face on the obstacle grid, the house being turned.)
	var g := BattleSim.new()
	g.setup(sc, 1)
	var q := t + o * 8.0
	var inb := false
	for k in 40:
		var b := g.obs_kind(int(q.x * M), int(q.y * M)) == MapGen.C_BUILDING
		if inb and not b:
			break
		inb = inb or b
		q += o * 0.5
	if inb:
		t = q - o * 8.0
	var s := t + o * dist
	var fa := int(round(atan2(-o.y, -o.x) / TAU * 1024.0)) & 1023
	sc["units"] = [Scenarios.unit(0, UT.index_of(sk), 60, int(s.x), int(s.y), fa, 20),
		Scenarios.unit(1, UT.index_of("w_pikemen"), 40, int(t.x), int(t.y), (fa + 512) & 1023, 16)]
	sc["ai_sides"] = [0] if mode == "ai" else []
	sc["orders"] = []
	sc["los"] = los
	sc["time_limit"] = 600
	sc.erase("deploy_zones")
	return sc


## A West walled town's breach (fourth pass of cover, 2026-11-06; the third evaluation's breach_rub): the town of
## seed 12 at walls 1, the longest wall stretch of 30 m or more with open ground 40 m out and in; a musket line of 40
## (side 1) 5 m `side` ("inside" or "outside") of its middle facing across it, 60 musketeers (side 0) 40 m on the
## other side facing back. The stretch's index is "_breach" (the caller breaches it after setup:
## BattleSim._breach(sg, -1)). (The town stands on ground about 2 m higher than outside the wall.)
static func breach_scenario(side: String) -> Dictionary:
	var city := {"seed": 12, "level": 2, "walls": 1, "bld": [1, 2, 4], "plan": MapGen.CUL_LATIN, "coast": 0,
		"founder": MapGen.CUL_LATIN, "west": 1}
	var terr := {"kind": Terrain.K_FLAT, "seed": 44, "forest": 0, "ground": MapGen.PAL_GREEN}
	var sc: Dictionary = Scenarios.settlement(city, terr, [[UT.index_of("musketeers"), 40]],
		[[UT.index_of("musketeers"), 40]], 1, [])["scenario"]
	sc["ai_sides"] = []
	sc["orders"] = []
	sc["time_limit"] = 600
	sc.erase("deploy_zones")
	var g := BattleSim.new()
	g.setup(sc, 1)
	var best := -1
	var bl := 0
	for sg in g.ws_x0.size():
		var l := FM.approx_len(g.ws_x1[sg] - g.ws_x0[sg], g.ws_y1[sg] - g.ws_y0[sg])
		var mx := (g.ws_x0[sg] + g.ws_x1[sg]) / 2
		var my := (g.ws_y0[sg] + g.ws_y1[sg]) / 2
		var dc := FM.cos_a(g.ws_dir[sg])
		var ds := FM.sin_a(g.ws_dir[sg])
		var ok := true
		for dd in [-40, -3, 3, 40]:
			var qx: int = mx + dc * dd * 1024 / FM.TRIG_ONE
			var qy: int = my + ds * dd * 1024 / FM.TRIG_ONE
			if qx < 20 * 1024 or qy < 20 * 1024 or qx > g.field_w - 20 * 1024 or qy > g.field_h - 20 * 1024 \
					or (absi(dd) == 40 and (g.obs_kind(qx, qy) != 0 or (g.nav_at(qx, qy) & 1) == 0)):
				ok = false
				break
		if ok and l > bl and l >= 30 * 1024:
			bl = l
			best = sg
	if best < 0:
		return {}
	var mx2: int = (g.ws_x0[best] + g.ws_x1[best]) / 2
	var my2: int = (g.ws_y0[best] + g.ws_y1[best]) / 2
	var dir: int = g.ws_dir[best]
	var c := FM.cos_a(dir)
	var sn := FM.sin_a(dir)
	var sg := 1 if side == "outside" else -1
	var face_line := (dir + (512 if side == "outside" else 0)) & 1023
	sc["units"] = [Scenarios.unit(0, UT.index_of("musketeers"), 60, (mx2 - sg * c * 40 * 1024 / FM.TRIG_ONE) / 1024,
			(my2 - sg * sn * 40 * 1024 / FM.TRIG_ONE) / 1024, (face_line + 512) & 1023, 15),
		Scenarios.unit(1, UT.index_of("musketeers"), 40, (mx2 + sg * c * 5 * 1024 / FM.TRIG_ONE) / 1024,
			(my2 + sg * sn * 5 * 1024 / FM.TRIG_ONE) / 1024, face_line, 10)]
	sc["_breach"] = best
	return sc


static func _num(sim, key: String) -> int:
	var v = sim.get(key)
	return int(v) if v != null else 0


static func crosses_house(sim, x0: int, y0: int, x1: int, y1: int) -> bool:
	var d := maxi(int(Vector2(x1 - x0, y1 - y0).length()), 1)
	var a := 2 * M
	while a < d - 2 * M:
		if sim.obs_kind(x0 + (x1 - x0) * a / d, y0 + (y1 - y0) * a / d) == MapGen.C_BUILDING:
			return true
		a += M / 2
	return false


static func run(weapon: String, pos: String, dist: int, mode: String, secs: int, sd: int = 7) -> Dictionary:
	var sim := BattleSim.new()
	sim.setup(scenario(weapon, pos, dist, mode), sd)
	if mode == "atk":
		sim.queue_order(BattleSim.make_attack_order(0, 0, 1, 0))
	var x0: int = sim.u_cx[0]
	var y0: int = sim.u_cy[0]
	var lof0 := -1
	var thru := 0
	var shots := 0
	var first_t := -1
	for k in secs * BattleSim.TICKS_PER_SECOND:
		var tb: int = sim.tick
		sim.step()
		if k == 1:
			lof0 = 1 if sim.lof_units(0, 1) else 0
		# (fresh shots: stat_shots grew; scan the pool for this tick's)
		var ns: int = _num(sim, "stat_shots")
		if ns > shots:
			if first_t < 0:
				first_t = k
			for p in sim.pr_t0.size():
				if sim.pr_t0[p] == tb and sim.pr_unit[p] == 0:
					if crosses_house(sim, sim.pr_sx[p], sim.pr_sy[p], sim.pr_x[p], sim.pr_y[p]):
						thru += 1
			shots = ns
		if sim.winner >= 0:
			break
	var dec := 0
	if sim.n_units > 2:
		dec = sim.u_count0[2] - sim.u_alive[2]
	return {"shots": shots, "lost": sim.u_count0[1] - sim.u_alive[1], "dec": dec,
		"blk": _num(sim, "stat_lof_blocked"), "fblk": _num(sim, "stat_flat_block"), "thru": thru,
		"moved": int(Vector2(sim.u_cx[0] - x0, sim.u_cy[0] - y0).length()) / M,
		"first": first_t / BattleSim.TICKS_PER_SECOND if first_t >= 0 else -1, "lof0": lof0,
		"lof1": 1 if sim.lof_units(0, 1) else 0, "seen": sim.u_seen[1] if sim.vis_on != 0 else 1,
		"ammo": sim.u_ammo[0]}


func _init() -> void:
	var secs := 60
	var only := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--secs="):
			secs = int(a.get_slice("=", 1))
		elif a.begins_with("--only="):
			only = a.get_slice("=", 1)
		elif a.begins_with("--los="):
			los = int(a.get_slice("=", 1))
	print("| weapon | target | dist m | mode | lof at start | shots | pikes lost | decoy lost | blocked (think) | stopped in flight | drawn across house | walked m | first shot s | lof at end | seen at end |")
	print("|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|")
	for weapon in ["musket", "bow"]:
		if only != "" and weapon != only:
			continue
		for pos in ["hidden", "half", "beside", "town"]:
			for dist in [40, 120]:
				for mode in ["atk", "faw", "faw2", "ai"]:
					var r := run(weapon, pos, dist, mode, secs)
					print("| %s | %s | %d | %s | %d | %d | %d | %d | %d | %d | %d | %d | %d | %d | %d |" % [weapon, pos, dist, mode,
						r["lof0"], r["shots"], r["lost"], r["dec"], r["blk"], r["fblk"], r["thru"], r["moved"], r["first"],
						r["lof1"], r["seen"]])
	quit()
