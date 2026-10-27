extends SceneTree
## The defending side of an open West town against a musket line at the front of the attackers' deployment zone
## (owner's phone playtest 2026-10-27: "the standard city defenders position a pike out front, who just gets
## annihilated every time the player places a line of musketeers right at the front of his preparation zone").
## A West campaign town on its own plan (as tests/town_balance.gd --town=west:<key>), the West sets' armies, the
## defenders the AI (the siege AI as in the campaign; --skill=0/1/2), the attackers scripted like the owner: in the
## deployment phase every musket-armed foot company (musketeers, buccaneers) is placed in one line along the front
## edge of the attackers' zone (fire at will, then Hold stance), the rest of the army 40 m behind; nobody moves for
## --hold minutes (default 4), then the attackers become the AI (Average) and assault so the battle ends.
## Prints a line a seed and a summary:
##   win      the attackers won
##   pre      defenders' men down before the first melee contact (any unit fighting hand to hand), by class:
##            pk pikes, sh shock / other melee foot, mu line muskets, sk skirmishers (cover troops); + the attackers'
##   inR      defender units (off the walls, not the fort) whose post at the start (after the first think: a street
##            post, a held building's door, else where they stand) is within an attacking line gun's range of it
##   pd       per class the nearest post's distance (m) to the musket line at the start
##   react    minutes from the start to the first defender unit that was in a line gun's range having lost men and is
##            out of it (+10 m) before the attackers' advance, or charges an attacker outside the town (an attack order on a unit not on urban ground); "-" none
##   contact  minutes to the first melee contact
##   godot --headless --script res://tests/defend_probe.gd -- --town=havana [--walls=0] [--skill=1] [--seeds=8]
##       [--seed0=0] [--hold=4] [--step=M (a minute in, the line walks M m toward the town and halts)] [--json=PATH]
##       [--trace=1]
const CData := preload("res://campaign/cdata.gd")
const CState := preload("res://campaign/cstate.gd")
const CTown := preload("res://campaign/ctown.gd")
const BattleSim := preload("res://sim/battle_sim.gd")
const Scenarios := preload("res://sim/scenarios.gd")
const SiegeAI := preload("res://sim/siege_ai.gd")
const UT := preload("res://sim/unit_types.gd")
const FM := preload("res://sim/fixed_math.gd")
const MapGen := preload("res://sim/mapgen.gd")

const M := 1024
const KS := ["pk", "sh", "mu", "sk"]


func _initialize() -> void:
	var town := "havana"
	var skill := 1
	var seeds := 8
	var seed0 := 0
	var walls := 0
	var hold := 4
	var step := 0
	var trace := false
	var jf: FileAccess = null
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--json="):
			jf = FileAccess.open(a.substr(7), FileAccess.WRITE)
		elif a.begins_with("--town="):
			town = a.get_slice("=", 1)
		elif a.begins_with("--skill="):
			skill = int(a.get_slice("=", 1))
		elif a.begins_with("--seeds="):
			seeds = int(a.get_slice("=", 1))
		elif a.begins_with("--seed0="):
			seed0 = int(a.get_slice("=", 1))
		elif a.begins_with("--walls="):
			walls = int(a.get_slice("=", 1))
		elif a.begins_with("--step="):
			step = int(a.get_slice("=", 1))
		elif a.begins_with("--hold="):
			hold = int(a.get_slice("=", 1))
		elif a == "--trace=1":
			trace = true
	var sums := {"win": 0, "pre_att": 0, "inr": 0, "react": 0, "react_n": 0, "contact": 0, "contact_n": 0, "kia": 0,
		"kid": 0, "t": 0, "pre": 0}
	for k in KS:
		sums["pre_" + k] = 0
		sums["pd_" + k] = 0
		sums["pdn_" + k] = 0
	for s in range(seed0, seed0 + seeds):
		var r := _run(town, walls, skill, s, hold, trace, step)
		var pds := ""
		for k in KS:
			pds += " %s %s" % [k, str(r["pd_" + k]) if r["pd_" + k] >= 0 else "-"]
		print("DFP %s w%d sk%d s%d: win %d  pre def %d (pk %d sh %d mu %d sk %d) att %d  inR %d/%d  pd%s  react %s  contact %s  end %.1f min  killed att %d def %d" % [
			town, walls, skill, s, r["win"], r["pre"], r["pre_pk"], r["pre_sh"], r["pre_mu"], r["pre_sk"], r["pre_att"],
			r["inr"], r["n_def"], pds, _min(r["react"]), _min(r["contact"]), r["t"] / 600.0, r["kia"], r["kid"]])
		if jf != null:
			var jr: Dictionary = r.duplicate()
			jr["probe"] = "defend"
			jr["town"] = town
			jr["skill"] = skill
			jr["seed"] = s
			jr["walls"] = walls
			jf.store_line(JSON.stringify(jr))
			jf.flush()
		for k in ["win", "pre_att", "inr", "kia", "kid", "t", "pre"]:
			sums[k] += r[k]
		for k in KS:
			sums["pre_" + k] += r["pre_" + k]
			if r["pd_" + k] >= 0:
				sums["pd_" + k] += r["pd_" + k]
				sums["pdn_" + k] += 1
		if r["react"] >= 0:
			sums["react"] += r["react"]
			sums["react_n"] += 1
		if r["contact"] >= 0:
			sums["contact"] += r["contact"]
			sums["contact_n"] += 1
	var n := maxi(seeds, 1)
	var pds2 := ""
	for k in KS:
		pds2 += " %s %s" % [k, ("%.0f" % (float(sums["pd_" + k]) / sums["pdn_" + k])) if sums["pdn_" + k] > 0 else "-"]
	print("DFPSUM %s w%d sk%d: win %d/%d  pre def %.0f (pk %.0f sh %.0f mu %.0f sk %.0f) att %.0f  inR %.1f  pd%s  react %s (%d/%d)  contact %s  end %.1f min  killed att %.0f def %.0f" % [
		town, walls, skill, sums["win"], seeds, float(sums["pre"]) / n, float(sums["pre_pk"]) / n, float(sums["pre_sh"]) / n,
		float(sums["pre_mu"]) / n, float(sums["pre_sk"]) / n, float(sums["pre_att"]) / n, float(sums["inr"]) / n, pds2,
		("%.1f" % (float(sums["react"]) / sums["react_n"] / 600.0)) if sums["react_n"] > 0 else "-", sums["react_n"], seeds,
		("%.1f" % (float(sums["contact"]) / sums["contact_n"] / 600.0)) if sums["contact_n"] > 0 else "-",
		float(sums["t"]) / n / 600.0, float(sums["kia"]) / n, float(sums["kid"]) / n])
	quit(0)


static func _min(t: int) -> String:
	return ("%.1f" % (t / 600.0)) if t >= 0 else "-"


## The probe's class of a defending unit: 0 pikes, 1 other melee foot, 2 line muskets (missile, not cover troops),
## 3 skirmishers (cover troops); -1 horse, guns, characters.
static func _kcls(sim, u: int) -> int:
	var c: int = sim.u_cls[u]
	if c == UT.CLS_PIKE:
		return 0
	if c == UT.CLS_INF:
		return 1
	if c == UT.CLS_MISSILE:
		return 3 if sim.t_cover[sim.u_otype[u]] != 0 else 2
	return -1


func _run(town: String, walls: int, skill: int, s: int, hold: int, trace: bool, step: int) -> Dictionary:
	var sc := _town_scenario(town, walls)
	sc["ai_sides"] = [1]
	sc["ai_skill"] = [1, skill]
	sc["deploy_time"] = -1
	sc["deploy_need"] = 1
	var sim := BattleSim.new()
	sim.setup(sc, 53000 + s * 197)
	var line := _script_attacker(sim)
	sim.queue_order({"tick": 0, "type": BattleSim.ORDER_READY, "who": 0, "player": 0})
	var guard := 0
	while sim.phase == BattleSim.PHASE_DEPLOY and guard < 100:
		sim.step()
		guard += 1
	for u in line:
		sim.queue_order({"tick": sim.tick, "type": SiegeAI.ORDER_STANCE, "unit": u, "stance": SiegeAI.STANCE_HOLD, "player": 0})
	var r := {"win": 0, "pre": 0, "pre_att": 0, "inr": 0, "n_def": 0, "react": -1, "contact": -1, "t": 0, "kia": 0, "kid": 0}
	for k in KS:
		r["pre_" + k] = 0
		r["pd_" + k] = -1
	var t0: int = sim.tick
	sim.step()
	# The posts after the first think.
	var inr0 := PackedByteArray()
	inr0.resize(sim.n_units)
	for u in sim.n_units:
		if sim.u_side[u] != 1 or sim.u_state[u] != 0 or sim.u_wall[u] > 0 or sim.in_fort(u) or _kcls(sim, u) < 0:
			continue
		r["n_def"] += 1
		var px: int = sim.u_cx[u]
		var py: int = sim.u_cy[u]
		if sim.u_ai[u] == SiegeAI.A_RESERVE or sim.u_ai[u] == SiegeAI.A_CIT:
			px = sim.u_ai_x[u]
			py = sim.u_ai_y[u]
		var bd := 1 << 40
		var hit := false
		for e in line:
			var d := FM.approx_len(sim.u_cx[e] - px, sim.u_cy[e] - py)
			bd = mini(bd, d)
			if d <= sim.mrange(e):
				hit = true
		if hit:
			r["inr"] += 1
			inr0[u] = 1
		var kk: String = KS[_kcls(sim, u)]
		if r["pd_" + kk] < 0 or bd / M < r["pd_" + kk]:
			r["pd_" + kk] = bd / M
		if trace:
			print("  post u%d %s cls %s mode %d dist %d m in %d" % [u, UT.key_of(sim.u_type[u]), kk, sim.u_ai[u], bd / M, 1 if hit else 0])
	var released := false
	var was_in := PackedByteArray()
	was_in.resize(sim.n_units)
	while sim.tick < sim.time_limit + 10 and sim.winner < 0:
		if step > 0 and sim.tick - t0 == 600:
			# (--step: a minute in, the line walks `step` m toward the town and halts there.)
			for e in line:
				if sim.u_state[e] != 0:
					continue
				var f: int = sim.u_face[e]
				sim.queue_order({"tick": sim.tick, "type": 1, "unit": e, "x": sim.u_ax[e] + FM.cos_a(f) * step * M / FM.TRIG_ONE,
					"y": sim.u_ay[e] + FM.sin_a(f) * step * M / FM.TRIG_ONE, "facing": f, "width": 0, "run": 0, "player": 0})
		if not released and sim.tick - t0 >= hold * 600:
			released = true
			sim.ai_sides[0] = 1
		sim.step()
		if r["contact"] < 0:
			for u in sim.n_units:
				if sim.u_state[u] == 0 and sim.u_fighting[u] > 0:
					r["contact"] = sim.tick - t0
					break
			if r["contact"] >= 0:
				for u in sim.n_units:
					var dn: int = sim.u_count0[u] - sim.u_alive[u]
					if sim.u_side[u] == 0:
						r["pre_att"] += dn
					elif _kcls(sim, u) >= 0:
						r["pre"] += dn
						r["pre_" + KS[_kcls(sim, u)]] += dn
		if r["react"] < 0 and sim.tick % 10 == 0:
			for u in sim.n_units:
				if sim.u_side[u] != 1 or sim.u_state[u] != 0 or sim.u_wall[u] > 0 or _kcls(sim, u) < 0:
					continue
				if sim.u_order[u] == 2 and sim.u_target[u] >= 0 and sim.u_side[sim.u_target[u]] == 0 \
						and (sim.veg_bits(sim.u_cx[sim.u_target[u]], sim.u_cy[sim.u_target[u]]) & MapGen.V_URBAN) == 0 \
						and _kcls(sim, u) != 2 and _kcls(sim, u) != 3:
					r["react"] = sim.tick - t0
					break
				var inn := false
				var near := false
				for e in line:
					if sim.u_state[e] != 0:
						continue
					var d := FM.approx_len(sim.u_cx[e] - sim.u_cx[u], sim.u_cy[e] - sim.u_cy[u])
					if d <= sim.mrange(e):
						inn = true
					if d <= sim.mrange(e) + 10 * M:
						near = true
				if inn and sim.u_alive[u] < sim.u_count0[u]:
					was_in[u] = 1  # (in reach and shot at)
				elif was_in[u] != 0 and not near and not released:
					r["react"] = sim.tick - t0
					break
		if trace and sim.tick % (150 if sim.tick - t0 > 300 else 20) == 0 and r["contact"] < 0:
			var ln := "  t %.2f:" % ((sim.tick - t0) / 600.0)
			for u in sim.n_units:
				if sim.u_side[u] == 1 and _kcls(sim, u) >= 0 and sim.u_wall[u] == 0 and (sim.u_state[u] == 0 or sim.tick - t0 < 300):
					var bd2 := 1 << 40
					for e in line:
						bd2 = mini(bd2, FM.approx_len(sim.u_cx[e] - sim.u_cx[u], sim.u_cy[e] - sim.u_cy[u]))
					ln += " %s/s%d/m%d/o%d/t%d/%dm/post%dm/%d" % [UT.key_of(sim.u_type[u]).substr(0, 4), sim.u_state[u], sim.u_ai[u], sim.u_order[u],
						sim.u_target[u], bd2 / M, FM.approx_len(sim.u_ai_x[u] - sim.u_cx[u], sim.u_ai_y[u] - sim.u_cy[u]) / M, sim.u_alive[u]]
			print(ln)
	if r["contact"] < 0:
		for u in sim.n_units:
			var dn2: int = sim.u_count0[u] - sim.u_alive[u]
			if sim.u_side[u] == 0:
				r["pre_att"] += dn2
			elif _kcls(sim, u) >= 0:
				r["pre"] += dn2
				r["pre_" + KS[_kcls(sim, u)]] += dn2
	r["win"] = 1 if sim.winner == 0 else 0
	r["t"] = (sim.decided_tick if sim.decided_tick >= 0 else sim.tick) - t0
	var res := sim.result()
	r["kia"] = int(res["sides"][0]["killed"])
	r["kid"] = int(res["sides"][1]["killed"])
	return r


## The owner's attack: every musket-armed foot company in one line along the front edge of the attackers' zone
## (fire at will), the rest 40 m behind it. Returns the line's units.
func _script_attacker(sim) -> Array:
	var z: PackedInt32Array = sim.dep_z
	var x0 := 0
	var x1: int = sim.field_w
	var yf := 0
	for k in range(0, z.size(), 6):
		if z[k] == 0:
			x0 = z[k + 2]
			x1 = z[k + 4]
			yf = z[k + 3]
	var cx := 0
	var n := 0
	for u in sim.n_units:
		if sim.u_side[u] == 0:
			cx += sim.u_cx[u] / M
			n += 1
	cx = cx / maxi(n, 1) * M
	var guns: Array = []
	var rest: Array = []
	for u in sim.n_units:
		if sim.u_side[u] != 0:
			continue
		if UT.stat(sim.u_type[u], "m_gun") != 0 and sim.u_cls[u] == UT.CLS_MISSILE:
			guns.append(u)
		else:
			rest.append(u)
	var face: int = sim.u_face[guns[0]] if not guns.is_empty() else 0
	var gap := 34 * M
	for i in guns.size():
		var u: int = guns[i]
		var x := clampi(cx + (i * 2 - (guns.size() - 1)) * gap / 2, x0 + 20 * M, x1 - 20 * M)
		sim.queue_order({"tick": 0, "type": BattleSim.ORDER_PLACE, "unit": u, "x": x, "y": yf + 4 * M, "facing": face,
			"files": 25, "player": 0})
		sim.queue_order({"tick": 0, "type": SiegeAI.ORDER_FIRE, "unit": u, "on": 1, "player": 0})
	for i in rest.size():
		var u: int = rest[i]
		var x := clampi(cx + (i * 2 - (rest.size() - 1)) * 30 * M / 2, x0 + 20 * M, x1 - 20 * M)
		sim.queue_order({"tick": 0, "type": BattleSim.ORDER_PLACE, "unit": u, "x": x, "y": yf + 44 * M, "facing": face,
			"player": 0})
	return guns


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
func _town_scenario(key: String, walls: int) -> Dictionary:
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
