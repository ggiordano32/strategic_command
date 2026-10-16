extends SceneTree
## Real cover probe (docs/PATHING_SPEC.md addendum 1, pathing phase C0):
## a firing duel, 100 musketeers 90 m off against a 60-man unit (buccaneers:
## cover trait; or line musketeers) standing in the open, in a rocky field
## (scattered boulders round it), in a hamlet (a field map's grid of house
## blocks round it: not drawn by the view) or across a street's mouth in an
## open Punic town (test_cover_town's ground), 90 s, several seeds. Prints per case the men each side lost, the
## casualty ratio (defender lost / attacker lost), the flat shots stopped on
## the way (stat_flat_block where the sim has it), the share of the
## defenders' men with an obstacle at least 1.2 m tall within 3 m toward
## the shooters at the end ("behind cover"), and how far the defenders' men
## stand from their formation places on average (line men must not
## scatter). Runs on any build (fields the sim lacks read 0), so a HEAD copy
## gives the before numbers.
##   godot --headless --script res://tests/cover_probe.gd [-- --seeds=4 --ticks=900]

const BattleSim := preload("res://sim/battle_sim.gd")
const Scenarios := preload("res://sim/scenarios.gd")
const UT := preload("res://sim/unit_types.gd")
const Terrain := preload("res://sim/terrain.gd")
const MapGen := preload("res://sim/mapgen.gd")
const FM := preload("res://sim/fixed_math.gd")
const M := 1024


static func _terrain(place: String) -> Dictionary:
	if place == "rocks":
		# Scattered boulders (2-4 m across, 1.6-2.4 m tall) among and just
		# before the defenders' line (front y 160, facing +y): within 5 m of
		# them, so the unit's line of fire stays open.
		var rk: Array = []
		var k := 0
		for y in [155, 163]:
			var x := 170 + k * 4
			while x <= 232:
				rk.append([x, y + (x * 7 % 3) - 1, 1 + (x % 2), 16 + (x * 3 % 9)])
				x += 6 + (x * 5 % 4)
			k += 1
		return {"kind": Terrain.K_FLAT, "rocks": rk}
	if place == "hamlet":
		# Houses 8 x 6 m in blocks, lanes 5 m, round the defenders.
		var bl: Array = []
		for j in 3:
			for i in 6:
				var x0 := 166 + i * 13
				var y0 := 133 + j * 11
				bl.append([x0, y0, x0 + 8, y0 + 6])
		return {"kind": Terrain.K_FLAT, "blocks": bl, "urban": [[160, 140, 245, 185]]}
	return {"kind": Terrain.K_FLAT}


static func _sc(def_key: String, place: String) -> Dictionary:
	if place == "town":
		return _town(UT.index_of(def_key), UT.index_of("musketeers"))
	# (In the hamlet: in the street behind the front row of houses, 150-155.)
	var t := Scenarios.unit(1, UT.index_of(def_key), 60, 200, 153 if place == "hamlet" else 160, Scenarios.FACE_DOWN)
	t["files"] = 30
	var sc := {"width_m": 400, "height_m": 400, "ai_sides": [], "orders": [], "units": [
		t, Scenarios.unit(0, UT.index_of("musketeers"), 100, 200, 250, Scenarios.FACE_UP)],
		"terrain": _terrain(place)}
	return sc


## The town of Scenarios.cover_town (test_cover_town), built here from
## Scenarios.settlement so the probe runs on builds without it: an open
## Punic town, the defenders (unit 0, 12 files) across a main street where
## houses flank it, facing out; 100 musketeers 90 m out.
static func _town(def_ty: int, att_ty: int) -> Dictionary:
	var city := {"seed": 707, "level": 2, "walls": 0, "bld": [1, 2, 4], "plan": MapGen.PLAN_PUNIC, "coast": 0}
	var terr := {"kind": Terrain.K_FLAT, "seed": 710, "forest": 0, "ground": MapGen.PAL_GREEN}
	var r := Scenarios.settlement(city, terr, [[att_ty, 100]], [[def_ty, 60]], 0, [])
	var sc: Dictionary = r["scenario"]
	var lay: Dictionary = r["layout"]
	var pl: Array = lay.get("agora", lay["plaza"])
	var spot: Array = []
	for mo in lay["mouths"]:
		var dx := int(mo[0]) - int(pl[0])
		var dy := int(mo[1]) - int(pl[1])
		var l := maxi(FM.isqrt(dx * dx + dy * dy), 1)
		var t := 0
		while t < l and spot.is_empty():
			var px := int(mo[0]) - dx * t / l
			var py := int(mo[1]) - dy * t / l
			var near := 0
			for b in lay["buildings"]:
				var bb: Array = b
				var ex := maxi(maxi(mini(int(bb[0]), int(bb[2])) - px, px - maxi(int(bb[0]), int(bb[2]))), 0)
				var ey := maxi(maxi(mini(int(bb[1]), int(bb[3])) - py, py - maxi(int(bb[1]), int(bb[3]))), 0)
				if ex * ex + ey * ey <= 36:
					near += 1
			if near >= 2:
				spot = [px, py, dx, dy, l]
			t += 2
		if not spot.is_empty():
			break
	var face := FM.atan2_a(spot[3], spot[2])
	var d := Scenarios.unit(0, def_ty, 60, spot[0], spot[1], face, 12)
	var a := Scenarios.unit(1, att_ty, 100, spot[0] + spot[2] * 90 / spot[4], spot[1] + spot[3] * 90 / spot[4], (face + 512) & 1023)
	sc["units"] = [d, a]
	sc["ai_sides"] = []
	sc["orders"] = []
	sc.erase("deploy_zones")
	return sc


static func _num(sim, key: String) -> int:
	var v = sim.get(key)
	return int(v) if v != null else 0


## A man at (x, y) has an obstacle >= 1.2 m within 3 m toward (tx, ty).
static func _behind(sim, x: int, y: int, tx: int, ty: int) -> bool:
	if sim.obs_on == 0:
		return false
	var dx := tx - x
	var dy := ty - y
	var d := maxi(int(sqrt(float(dx) * dx + float(dy) * dy)), 1)
	var a := 512
	while a <= 3 * M:
		var px := x + dx * a / d
		var py := y + dy * a / d
		var k: int = sim.obs_kind(px, py)
		if k == MapGen.C_BUILDING:
			return true
		if MapGen.is_land(k) and int(sim._obs_top(px, py)) >= 1229:
			return true
		a += 512
	return false


func _run(def_key: String, place: String, sd: int, ticks: int) -> Dictionary:
	var sim := BattleSim.new()
	sim.setup(_sc(def_key, place), sd)
	sim.queue_order({"tick": 0, "type": BattleSim.ORDER_SKIRMISH, "unit": 0, "on": 0, "player": 50})
	sim.queue_order(BattleSim.make_attack_order(0, 1, 0, 0))
	var us := 0
	for k in ticks:
		var t0 := Time.get_ticks_usec()
		sim.step()
		us += Time.get_ticks_usec() - t0
	var behind := 0
	var disp := 0
	var base: int = sim.u_slot_base[0]
	var alive: int = sim.u_alive[0]
	for s in alive:
		var i: int = sim.slot_soldier[base + s]
		if _behind(sim, sim.pos_x[i], sim.pos_y[i], sim.u_cx[1], sim.u_cy[1]):
			behind += 1
		var px: int = sim.u_ax[0] + sim.off_x[base + s]
		var py: int = sim.u_ay[0] + sim.off_y[base + s]
		disp += int(sqrt(float(sim.pos_x[i] - px) ** 2 + float(sim.pos_y[i] - py) ** 2))
	return {"lost_d": sim.u_count0[0] - sim.u_alive[0], "lost_a": sim.u_count0[1] - sim.u_alive[1],
		"block": _num(sim, "stat_flat_block"), "traced": _num(sim, "stat_flat_traced"),
		"cstop": _num(sim, "stat_cover_stop"), "gstop": _num(sim, "stat_ground_stop"),
		"behind": behind, "alive": alive, "disp": disp, "ms": us / 1000.0 / ticks,
		"spots": _num(sim, "stat_cs_men")}


func _init() -> void:
	var seeds := 4
	var ticks := 900
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seeds="):
			seeds = int(a.get_slice("=", 1))
		elif a.begins_with("--ticks="):
			ticks = int(a.get_slice("=", 1))
	print("case                 lost def / att   ratio   blocked/traced  cover/ground stops  behind cover  disp m  ms/tick")
	for def_key in ["buccaneers", "musketeers"]:
		for place in ["open", "rocks", "hamlet", "town"]:
			var tot := {"lost_d": 0, "lost_a": 0, "block": 0, "traced": 0, "cstop": 0, "gstop": 0, "behind": 0,
				"alive": 0, "disp": 0, "ms": 0.0, "spots": 0}
			for k in seeds:
				var r := _run(def_key, place, 11 * (k + 1), ticks)
				for key in tot:
					tot[key] += r[key]
			print("%-10s %-6s  %6.1f / %5.1f   %5.2f   %6d / %6d   %5d / %5d     %5.1f %%     %5.2f   %.2f" % [
				def_key, place, tot["lost_d"] / float(seeds), tot["lost_a"] / float(seeds),
				tot["lost_d"] / maxf(tot["lost_a"], 1.0), tot["block"], tot["traced"], tot["cstop"], tot["gstop"],
				100.0 * tot["behind"] / maxf(tot["alive"], 1.0), tot["disp"] / 1024.0 / maxf(tot["alive"], 1.0),
				tot["ms"] / seeds])
	quit(0)
