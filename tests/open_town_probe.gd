extends SceneTree
## Open West town against a scripted house defender (owner's report 2026-10-20: "the AI armies sit back just in
## range of my musketeers and get picked off"). A campaign town on its own plan (as tests/town_balance.gd
## --town=west:<key>), walls 0, the West sets' armies; the attackers are the AI (--skill=1 Average, 2 Skilled), the
## defenders are scripted like the owner: every musket-armed foot company (musketeers, buccaneers; --occ=line: the
## musketeers only) is sent at once into the building nearest the street mouth it is given (the mouths nearest the
## attackers first, shared out; ORDER_OCCUPY at the run, fire at will), the rest hold the plaza (moved there, fire at
## will). Prints a line a seed and a summary:
##   win     the attackers won
##   L3a/L3d the attackers' / defenders' men down (count0 - alive) in the 3 minutes from contact (the first attacker
##           within 120 m of a held building)
##   dist    mean distance (m) of halted attacking line units (foot, not cover troops, not horse; ready, not
##           fighting, moved < 1 m in the second) to the nearest held building's door, over those 3 minutes
##   inR     unit-seconds those halted line units stood within 120 m (musket range) of a held building
##   band    unit-seconds the attacking missile units in the stand-off band (A_COVER) stood halted within 120 m
##   door    minutes to the first attacker at a held building's door (within 15 m), from contact
##   spw     unit-seconds attacking line units spent halted waiting off a strongpoint (C7 _sp_wait: its condition, or
##           the wait's memory u_ai_y > 0)
##   godot --headless --script res://tests/open_town_probe.gd -- --town=havana [--skill=1] [--seeds=8] [--seed0=0]
##       [--occ=all|line|mixed (musketeers in houses, buccaneers in cover at the mouths)] [--trace=1]
const CData := preload("res://campaign/cdata.gd")
const CState := preload("res://campaign/cstate.gd")
const CTown := preload("res://campaign/ctown.gd")
const BattleSim := preload("res://sim/battle_sim.gd")
const Scenarios := preload("res://sim/scenarios.gd")
const SiegeAI := preload("res://sim/siege_ai.gd")
const UT := preload("res://sim/unit_types.gd")
const FM := preload("res://sim/fixed_math.gd")

const M := 1024
const REACH := 120 * M


func _initialize() -> void:
	var town := "havana"
	var skill := 1
	var seeds := 8
	var seed0 := 0
	var occ_all := true
	var mixed := false
	var trace := false
	var walls := 0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--town="):
			town = a.get_slice("=", 1)
		elif a.begins_with("--skill="):
			skill = int(a.get_slice("=", 1))
		elif a.begins_with("--seeds="):
			seeds = int(a.get_slice("=", 1))
		elif a.begins_with("--seed0="):
			seed0 = int(a.get_slice("=", 1))
		elif a.begins_with("--walls="):
			walls = int(a.get_slice("=", 1))
		elif a == "--occ=line":
			occ_all = false
		elif a == "--occ=mixed":
			occ_all = false
			mixed = true
		elif a == "--trace=1":
			trace = true
	var sums := {"win": 0, "l3a": 0, "l3d": 0, "dist": 0, "dist_n": 0, "inr": 0, "band": 0, "door": 0, "door_n": 0,
		"spw": 0, "t": 0, "contact": 0, "kia": 0, "kid": 0}
	for s in range(seed0, seed0 + seeds):
		var r := _run(town, walls, skill, s, occ_all, trace, mixed)
		print("OTP %s sk%d s%d: win %d  L3 att %d def %d  dist %.0f m (n %d)  inR %d s  band %d s  door %s  spw %d s  held %d  contact %.1f min  end %.1f min  killed att %d def %d" % [
			town, skill, s, r["win"], r["l3a"], r["l3d"], float(r["dist"]) / maxi(r["dist_n"], 1), r["dist_n"], r["inr"],
			r["band"], ("%.1f" % (r["door"] / 600.0)) if r["door"] >= 0 else "-", r["spw"], r["held"], r["contact"] / 600.0,
			r["t"] / 600.0, r["kia"], r["kid"]])
		sums["win"] += r["win"]
		for k in ["l3a", "l3d", "dist", "dist_n", "inr", "band", "spw", "t", "contact", "kia", "kid"]:
			sums[k] += r[k]
		if r["door"] >= 0:
			sums["door"] += r["door"]
			sums["door_n"] += 1
	var n := maxi(seeds, 1)
	print("OTPSUM %s sk%d: win %d/%d  L3 att %.0f def %.0f  dist %.0f m  inR %.0f s  band %.0f s  door %s (%d/%d)  spw %.0f s  contact %.1f min  end %.1f min  killed att %.0f def %.0f" % [
		town, skill, sums["win"], seeds, float(sums["l3a"]) / n, float(sums["l3d"]) / n,
		float(sums["dist"]) / maxi(sums["dist_n"], 1), float(sums["inr"]) / n, float(sums["band"]) / n,
		("%.1f" % (float(sums["door"]) / maxi(sums["door_n"], 1) / 600.0)) if sums["door_n"] > 0 else "-",
		sums["door_n"], seeds, float(sums["spw"]) / n, float(sums["contact"]) / n / 600.0, float(sums["t"]) / n / 600.0,
		float(sums["kia"]) / n, float(sums["kid"]) / n])
	quit(0)


func _run(town: String, walls: int, skill: int, s: int, occ_all: bool, trace: bool, mixed: bool) -> Dictionary:
	var sc := _town_scenario(town, walls, s)
	sc["ai_sides"] = [0]
	sc["ai_skill"] = [skill, 1]
	var sim := BattleSim.new()
	sim.setup(sc, 53000 + s * 197)
	if trace:
		print("skill ", sim.ai_skill, " sides ", sim.ai_sides)
	var held_n := _script_defender(sim, occ_all, mixed)
	var lx := PackedInt32Array()
	var ly := PackedInt32Array()
	lx.resize(sim.n_units)
	ly.resize(sim.n_units)
	for u in sim.n_units:
		lx[u] = sim.u_cx[u]
		ly[u] = sim.u_cy[u]
	var r := {"win": 0, "l3a": 0, "l3d": 0, "dist": 0, "dist_n": 0, "inr": 0, "band": 0, "door": -1, "spw": 0, "held": held_n,
		"contact": -1, "t": 0, "kia": 0, "kid": 0}
	var c0 := -1
	var down0 := [0, 0]
	while sim.tick < sim.time_limit + 10 and sim.winner < 0:
		sim.step()
		if sim.tick % 10 != 0:
			continue
		var held := []
		for b in sim.ob_ok.size():
			if sim.ob_ok[b] != 0 and sim.ob_u[b] != 0 and sim.u_side[sim.ob_u[b] - 1] == 1 \
					and sim.u_state[sim.ob_u[b] - 1] == 0 and sim.u_occ[sim.ob_u[b] - 1] == b + 1:
				held.append(b)
		var in3: bool = c0 >= 0 and sim.tick - c0 <= 1800
		for u in sim.n_units:
			var moved := FM.approx_len(sim.u_cx[u] - lx[u], sim.u_cy[u] - ly[u])
			lx[u] = sim.u_cx[u]
			ly[u] = sim.u_cy[u]
			if sim.u_side[u] != 0 or sim.u_state[u] != 0 or held.is_empty():
				continue
			var bd := 1 << 40
			for b in held:
				bd = mini(bd, FM.approx_len(sim.ob_dx[b] - sim.u_cx[u], sim.ob_dy[b] - sim.u_cy[u]))
			if c0 < 0 and bd <= REACH:
				c0 = sim.tick
				down0 = [_down(sim, 0), _down(sim, 1)]
				r["contact"] = c0
				in3 = true
			if c0 >= 0 and r["door"] < 0 and bd <= 15 * M:
				r["door"] = sim.tick - c0
			var halted: bool = moved < M and sim.u_fighting[u] == 0 and sim.u_contact[u] == 0
			var line: bool = sim.t_cover[sim.u_otype[u]] == 0 and sim.u_cls[u] != UT.CLS_CAV and BattleSim.stance_ok(sim.u_type[u])
			if halted and line and sim.u_ai[u] == SiegeAI.A_STORM and (_sp_cond(sim, u) or sim.u_ai_y[u] > 0):
				r["spw"] += 1
			if not in3 or not halted:
				continue
			if line:
				r["dist"] += bd / M
				r["dist_n"] += 1
				if bd <= REACH:
					r["inr"] += 1
			if sim.u_ai[u] == SiegeAI.A_COVER and bd <= REACH:
				r["band"] += 1
		if c0 >= 0 and sim.tick - c0 == 1800:
			r["l3a"] = _down(sim, 0) - down0[0]
			r["l3d"] = _down(sim, 1) - down0[1]
		if trace and sim.tick % 300 == 0:
			var ln := "  t %.1f:" % (sim.tick / 600.0)
			for u in sim.n_units:
				if sim.u_side[u] == 0 and sim.u_state[u] == 0:
					ln += " %s/%d/%d" % [UT.key_of(sim.u_type[u]).substr(0, 4), sim.u_ai[u], sim.u_alive[u]]
			print(ln, "  held ", held.size())
	if c0 >= 0 and sim.tick - c0 < 1800:
		r["l3a"] = _down(sim, 0) - down0[0]
		r["l3d"] = _down(sim, 1) - down0[1]
	r["win"] = 1 if sim.winner == 0 else 0
	r["t"] = sim.decided_tick if sim.decided_tick >= 0 else sim.tick
	var res := sim.result()
	r["kia"] = int(res["sides"][0]["killed"])
	r["kid"] = int(res["sides"][1]["killed"])
	return r


static func _down(sim, side: int) -> int:
	var n := 0
	for u in sim.n_units:
		if sim.u_side[u] == side:
			n += sim.u_count0[u] - sim.u_alive[u]
	return n


## The C7 wait's condition (SiegeAI._sp_wait, without its order).
static func _sp_cond(sim, u: int) -> bool:
	if sim.ai_prog[2] != 0:
		return false
	for o in sim.n_units:
		if sim.u_side[o] == sim.u_side[u] or sim.u_state[o] != 0 or sim.u_cvb[o] < 0:
			continue
		if sim.u_alive[o] * 100 < sim.u_count0[o] * SiegeAI.SP_WORN or sim.u_disorder[o] >= 25:
			continue
		if FM.approx_len(sim.u_cx[o] - sim.u_cx[u], sim.u_cy[o] - sim.u_cy[u]) < SiegeAI.SP_WAIT_R:
			return true
	return false


## The owner's defence: musket companies into the houses at the street mouths, the rest to the plaza. Returns the
## buildings ordered.
func _script_defender(sim, occ_all: bool, mixed: bool) -> int:
	var lay: Dictionary = sim.map_info["city"]
	var mouths: Array = lay.get("mouths", [])
	# Attackers' centre.
	var ax := 0
	var ay := 0
	var an := 0
	for u in sim.n_units:
		if sim.u_side[u] == 0:
			ax += sim.u_cx[u] / M
			ay += sim.u_cy[u] / M
			an += 1
	ax = ax / maxi(an, 1) * M
	ay = ay / maxi(an, 1) * M
	var ix: Array = []
	for k in mouths.size():
		ix.append(k)
	ix.sort_custom(func(a, b):
		var da := FM.approx_len(int(mouths[a][0]) * M - ax, int(mouths[a][1]) * M - ay)
		var db := FM.approx_len(int(mouths[b][0]) * M - ax, int(mouths[b][1]) * M - ay)
		return da < db or (da == db and a < b))
	var orders: Array = []
	var taken := {}
	var k := 0
	var km := 0
	var px: int = sim.plaza[0]
	var py: int = sim.plaza[1]
	var nplaza := 0
	var held := 0
	for u in sim.n_units:
		if sim.u_side[u] != 1:
			continue
		var gun: bool = UT.stat(sim.u_type[u], "m_gun") != 0 and sim.u_cls[u] != UT.CLS_CAV and BattleSim.stance_ok(sim.u_type[u])
		var cover: bool = sim.t_cover[sim.u_otype[u]] != 0
		if gun and (occ_all or not cover) and not ix.is_empty() and sim.occ_on != 0:
			var mo: Array = mouths[ix[k % ix.size()]]
			k += 1
			# Just inside the mouth (10 % toward the plaza).
			var tx: int = int(mo[0]) * M + (px - int(mo[0]) * M) / 10
			var ty: int = int(mo[1]) * M + (py - int(mo[1]) * M) / 10
			var best := -1
			var bd := 1 << 40
			for b in sim.ob_ok.size():
				if sim.ob_ok[b] == 0 or taken.has(b) or sim.ob_sn[b] < SiegeAI.SP_OCC_MIN:
					continue
				var d := FM.approx_len(sim.ob_dx[b] - tx, sim.ob_dy[b] - ty)
				if d < bd:
					bd = d
					best = b
			if best >= 0:
				taken[best] = 1
				held += 1
				orders.append({"tick": 0, "type": BattleSim.ORDER_OCCUPY, "unit": u, "building": best, "run": 1, "player": 1})
				orders.append({"tick": 0, "type": SiegeAI.ORDER_FIRE, "unit": u, "on": 1, "player": 1})
				continue
		if gun and cover and mixed and not ix.is_empty():
			# (--occ=mixed: the buccaneers hold the street a quarter of the way in from the mouths, in cover.)
			var mo2: Array = mouths[ix[km % ix.size()]]
			km += 1
			var qx: int = int(mo2[0]) * M + (px - int(mo2[0]) * M) / 4
			var qy: int = int(mo2[1]) * M + (py - int(mo2[1]) * M) / 4
			var q: Vector2i = sim.open_snap(sim, qx, qy, sim._ground_mask(u))
			orders.append({"tick": 0, "type": 1, "unit": u, "x": q.x, "y": q.y, "facing": FM.atan2_a(int(mo2[1]) * M - qy, int(mo2[0]) * M - qx),
				"width": 0, "run": 1, "player": 1})
			orders.append({"tick": 0, "type": SiegeAI.ORDER_FIRE, "unit": u, "on": 1, "player": 1})
			continue
		var off := (nplaza % 4 - 1) * 14 * M
		var offy := (nplaza / 4 - 1) * 12 * M
		nplaza += 1
		orders.append({"tick": 0, "type": 1, "unit": u, "x": px + off, "y": py + offy, "facing": sim.u_face[u],
			"width": 0, "run": 1, "player": 1})
		if sim.u_cls[u] == UT.CLS_MISSILE or UT.stat(sim.u_type[u], "m_range") > 0:
			orders.append({"tick": 0, "type": SiegeAI.ORDER_FIRE, "unit": u, "on": 1, "player": 1})
	for o in orders:
		sim.queue_order(o)
	return held


## The campaign town's plan at this level and walls (CTown.battle_plan; as tests/town_balance.gd).
func _tp(pack: String, key: String, level: int, walls: int) -> Dictionary:
	CData.use_pack(pack)
	var st := CState.new_campaign("bal", 5, [], {}, [], pack)
	var r := CData.region_index(key)
	st["regions"][r]["level"] = level
	var got := false
	for sl in st["regions"][r]["slots"]:
		if int(sl[0]) == CData.WALLS:
			sl[1] = walls
			got = true
	if not got:
		st["regions"][r]["slots"].append([CData.WALLS, walls])
	return CTown.battle_plan(st, r)


## A West campaign town on its own plan (as tests/town_balance.gd --town=west:<key>).
func _town_scenario(key: String, walls: int, _s: int) -> Dictionary:
	CData.use_pack("west")
	var r := CData.region_index(key)
	var cul := CData.region_culture(r)
	var st0 := CState.new_campaign("bal", 5, [], {}, [], "west")
	var level := maxi(1, int(st0["regions"][r]["level"]))
	var rd: Dictionary = CData.REGIONS[r]
	var cseed := 0
	for ch in key.to_utf8_buffer():
		cseed = (cseed * 31 + int(ch)) % 100000
	var att: Array = []
	for e in Scenarios.WEST_ATT:
		att.append([UT.index_of(str(e[0])), int(e[1])])
	var dfn: Array = att.duplicate(true)
	var terr := {"kind": int(rd["terrain"]), "seed": cseed * 7 + 3, "forest": int(rd["forest"]), "ground": int(rd["ground"])}
	var city := {"seed": cseed, "level": level, "walls": walls, "bld": [1, 2, 4], "plan": cul,
		"coast": 1 if CData.is_port(r) else 0, "founder": cul, "west": 1}
	city["tp"] = _tp("west", key, level, walls)
	var eq := {"ladders": 3, "ram": 1} if walls > 0 else {}
	return Scenarios.settlement(city, terr, att, dfn, 1, [0, 1], eq)["scenario"]
