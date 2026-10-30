extends SceneTree
## The asymmetry probe (roles step 2; docs/design/battle_sim.md "Roles, step 2 (as built)"): the
## scenarios asym_woods and asym_field (a Spanish army, side 0, against a native war party of equal
## cost, both AI Average) over seeds; prints each battle and the side-0 (Spanish) win count.
##   godot --headless --script res://tests/asym_probe.gd -- --scen=asym_woods --seeds=16 [--seed0=0] [--plays=MASK]
## play_field (docs/AI.md 44.1): the Spanish against an English army on open
## ground (the English with England's campaign plays, the countermarch's
## bit only). --plays=MASK sets the Spanish side's ai_plays (sim/plays.gd
## bits; default every play), e.g. --plays=0 without the tercio. Each battle
## prints whether the Spanish formed a tercio, and the line of sight's
## reveals, hidden checks and sight lingers (the summary: per battle).
## The native ambush (docs/AI.md 44.5): --plays1=MASK sets the natives' (side
## 1) bits (e.g. --plays1=0 without the ambush, 4 with it only);
## ambush_field (the Spanish column between two woods). Each battle prints
## the ambush's counters (laid, springs, melts) and the sim's ambush strikes;
## the summary the natives' losses and the battle's length (means) too.
## --trace-amb: every 10 s a line per native unit (type, part, state, metres
## from its post, hidden from the Spanish, fire, target, men lost) and per
## Spanish unit (type, metres ahead of the woods' front, order, men lost);
## at the end a table per native type over all seeds (men lost, kills,
## springs, melts, seconds hidden / fighting / melting).
## The Swedish salvo (docs/AI.md 44.6): salvo_field (the English, side 1,
## with the salvo bit 8 against the Spanish); --plays1=2 without it, 10 with
## it (play_field likewise; --plays=7 keeps the salvo from the Spanish side,
## whose default there is every bit). Each battle prints both sides' salvos,
## volleys and charges; the SALVO summary line the men lost a battle on each
## side and, for side 1, the men its salvo lines lost while walking in
## (fire held, SV_HOLD) and the salvos, volleys and charges a battle.
## --knob=ID:VALUE sets a knob in every profile row (repeatable), e.g.
## --knob=336:2 the salvo's targets shooters only.

const BattleSim := preload("res://sim/battle_sim.gd")
const Scenarios := preload("res://sim/scenarios.gd")
const AP := preload("res://sim/ai_profile.gd")
const Plays := preload("res://sim/plays.gd")
const UT := preload("res://sim/unit_types.gd")
const FM := preload("res://sim/fixed_math.gd")


func _init() -> void:
	var scen := "asym_woods"
	var seeds := 16
	var seed0 := 0
	var plays := -2  # (-2: the scenario's own; else side 0's ai_plays)
	var plays1 := -2  # (... side 1's)
	var trace := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--scen="):
			scen = a.substr(7)
		elif a.begins_with("--seeds="):
			seeds = int(a.substr(8))
		elif a.begins_with("--seed0="):
			seed0 = int(a.substr(8))
		elif a.begins_with("--plays="):
			plays = int(a.substr(8))
		elif a.begins_with("--plays1="):
			plays1 = int(a.substr(9))
		elif a == "--trace-amb":
			trace = true
		elif a.begins_with("--knob="):
			# (--knob=ID:VALUE: every profile row's knob ID set to VALUE, for a
			# variant's measure without an edit; repeatable)
			var kv := a.substr(7).split(":")
			AP.row(0, 0)
			for i in AP._tab.size():
				var p: PackedInt32Array = AP._tab[i]
				p[int(kv[0])] = int(kv[1])
				AP._tab[i] = p
	var w := [0, 0, 0]
	var rv := 0
	var hd := 0
	var lg := 0
	var nl := 0
	var ln := 0
	var amb := [0, 0, 0, 0]
	var agg := {}  # native type key -> [lost, kills, springs, melts, t_hide, t_fight, t_melt, units]
	var sv := [0, 0, 0, 0, 0, 0, 0]  # side 0 lost, side 1 lost, side 1 closing losses, salvos, volleys, charges, side 0 salvos
	for k in seeds:
		var sd := 5000 + seed0 + k
		var sim := BattleSim.new()
		var sc := Scenarios.make(scen)
		if plays != -2 or plays1 != -2:
			var pl: Array = sc.get("ai_plays", [-1, -1])
			sc["ai_plays"] = [plays if plays != -2 else pl[0], plays1 if plays1 != -2 else pl[1]]
		sim.setup(sc, sd)
		var n1_0 := 0
		var n0_0 := 0
		for u in sim.n_units:
			if sim.u_side[u] == 1:
				n1_0 += sim.u_alive[u]
			else:
				n0_0 += sim.u_alive[u]
		var pst := {}
		var n0 := {}
		for u in sim.n_units:
			n0[u] = sim.u_alive[u]
		var lalive := {}
		var close_lost := 0
		while sim.tick < 12000 and sim.winner < 0:
			sim.step()
			if Plays.has_mem(sim) and Plays.salvo_on(sim, 1) and Plays._ps(sim, 1, Plays.PS_SV_PH) == Plays.SV_HOLD:
				for j in 2:
					var l := Plays._ps(sim, 1, Plays.PS_SV_L + j) - 1
					if l >= 0:
						close_lost += maxi(int(lalive.get(l, sim.u_alive[l])) - sim.u_alive[l], 0)
			for u in sim.n_units:
				lalive[u] = sim.u_alive[u]
			if trace:
				_trace_tick(sim, sd, pst, n0, agg)
		if trace:
			for u in sim.n_units:
				if sim.u_side[u] == 1:
					var a: Array = _agg_row(agg, UT.key_of(sim.u_otype[u]))
					a[0] += int(n0[u]) - sim.u_alive[u]
					a[1] += sim.u_kills[u]
					a[7] += 1
				else:
					var kk: Array = _agg_row(agg, "S:" + UT.key_of(sim.u_otype[u]))
					kk[7] += 1
					kk[1] += sim.u_kills[u]
					kk[0] += int(n0[u]) - sim.u_alive[u]
					for t in sim.kty_n:
						var c: int = sim.u_kills_ty[u * sim.kty_n + t]
						if c > 0:
							var kx: Array = _agg_row(agg, "K:" + UT.key_of(sim.u_otype[u]) + ">" + UT.key_of(t))
							kx[1] += c
		var r: int = sim.winner if sim.winner == 0 or sim.winner == 1 else 2
		w[r] += 1
		print("BATTLE %s seed %d winner %d tick %d alive %d/%d pistols %d car %d drift %d parley %d/%d pris %d,%d" % [scen, sd, r, sim.tick,
			sim.alive_count(0), sim.alive_count(1), sim.stat_pis_shots if "stat_pis_shots" in sim else -1,
			sim.stat_car_volleys if "stat_car_volleys" in sim else -1, sim.stat_skd_men if "stat_skd_men" in sim else -1,
			sim.stat_parley_ok, sim.stat_parley_ok + sim.stat_parley_fail, sim.ch_pris[0], sim.ch_pris[1]])
		var lin: int = sim.get("stat_lingers") if "stat_lingers" in sim else 0
		var na := AP.N_COUNTERS
		var lost1: int = n1_0 - sim.alive_count(1)
		print("  tercio %d reveals %d hidden %d lingers %d ambush %d springs %d melts %d strikes %d natives_lost %d spanish_lost %d" % [
			sim.stat_aic[AP.C_PLAY_TERCIO], sim.stat_reveals, sim.stat_hidden, lin, sim.stat_aic[na + AP.C_PLAY_AMBUSH],
			sim.stat_aic[na + AP.C_AMB_SPRING], sim.stat_aic[na + AP.C_AMB_MELT], sim.stat_ambush, lost1, n0_0 - sim.alive_count(0)])
		print("  salvo side0 %d/%d/%d side1 %d/%d/%d (salvos/volleys/charges) closing_lost %d" % [sim.stat_aic[AP.C_PLAY_SALVO],
			sim.stat_aic[AP.C_SALVO_VOLLEY], sim.stat_aic[AP.C_SALVO_CHARGE], sim.stat_aic[na + AP.C_PLAY_SALVO],
			sim.stat_aic[na + AP.C_SALVO_VOLLEY], sim.stat_aic[na + AP.C_SALVO_CHARGE], close_lost])
		sv[0] += n0_0 - sim.alive_count(0)
		sv[1] += lost1
		sv[2] += close_lost
		sv[3] += sim.stat_aic[na + AP.C_PLAY_SALVO]
		sv[4] += sim.stat_aic[na + AP.C_SALVO_VOLLEY]
		sv[5] += sim.stat_aic[na + AP.C_SALVO_CHARGE]
		sv[6] += sim.stat_aic[AP.C_PLAY_SALVO]
		amb[0] += sim.stat_aic[na + AP.C_PLAY_AMBUSH]
		amb[1] += sim.stat_aic[na + AP.C_AMB_SPRING]
		amb[2] += sim.stat_aic[na + AP.C_AMB_MELT]
		amb[3] += sim.stat_ambush
		nl += lost1
		ln += sim.tick
		lg += lin
		rv += sim.stat_reveals
		hd += sim.stat_hidden
	print("SUMMARY %s seeds %d spanish %d natives %d draws %d reveals/battle %.1f hidden/battle %.1f lingers/battle %.1f" % [scen, seeds, w[0], w[1], w[2],
		float(rv) / maxi(seeds, 1), float(hd) / maxi(seeds, 1), float(lg) / maxi(seeds, 1)])
	var sn := float(maxi(seeds, 1))
	print("AMBUSH %s natives_lost/battle %.1f length_s %.1f laid %d springs/battle %.2f melts/battle %.2f strikes/battle %.2f" % [scen,
		nl / sn, ln / sn / 10.0, amb[0], amb[1] / sn, amb[2] / sn, amb[3] / sn])
	print("SALVO %s side0_lost/battle %.1f side1_lost/battle %.1f side1_closing_lost/battle %.1f side1 salvos/battle %.2f volleys/battle %.2f charges/battle %.2f side0 salvos/battle %.2f" % [
		scen, sv[0] / sn, sv[1] / sn, sv[2] / sn, sv[3] / sn, sv[4] / sn, sv[5] / sn, sv[6] / sn])
	if trace:
		print("TYPE natives: type units lost kills springs melts s_hide s_fight s_melt (sums over seeds)")
		for k in agg.keys():
			var a: Array = agg[k]
			print("TYPE %-16s %3d lost %5d kills %5d springs %4d melts %4d hide %6d fight %6d melt %6d lostin hide %5d fight %5d melt %5d bait %5d free %5d" % [k, a[7], a[0], a[1], a[2], a[3], a[4] / 10, a[5] / 10, a[6] / 10, a[8], a[9], a[10], a[11], a[12]])
	quit()


static func _agg_row(agg: Dictionary, k: String) -> Array:
	if not agg.has(k):
		agg[k] = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
	return agg[k]


## --trace-amb: the per-tick tallies and the 10 s lines.
static func _trace_tick(sim, sd: int, pst: Dictionary, n0: Dictionary, agg: Dictionary) -> void:
	var on := Plays.has_mem(sim) and Plays.ambush_on(sim, 1)
	for u in sim.n_units:
		if sim.u_side[u] == 1:
			var pa: int = pst.get(u + 100000, int(n0[u]))
			var dl: int = pa - sim.u_alive[u]
			pst[u + 100000] = sim.u_alive[u]
			if dl > 0:
				var ar: Array = _agg_row(agg, UT.key_of(sim.u_otype[u]))
				var r0 := Plays._pm(sim, u, Plays.PU_ROLE) if on else 0
				if r0 < Plays.R_HIDE:
					ar[12] += dl
				elif r0 == Plays.R_BAIT:
					ar[11] += dl
				else:
					ar[8 + Plays._pm(sim, u, Plays.PU_STATE)] += dl
	for u in sim.n_units:
		if sim.u_side[u] != 1 or sim.u_state[u] != 0 or not on:
			continue
		var r := Plays._pm(sim, u, Plays.PU_ROLE)
		if r < Plays.R_HIDE:
			continue
		var st := Plays._pm(sim, u, Plays.PU_STATE)
		var a: Array = _agg_row(agg, UT.key_of(sim.u_otype[u]))
		var ps: int = pst.get(u, -1)
		if r != Plays.R_BAIT:
			if st == Plays.AS_FIGHT and ps != Plays.AS_FIGHT:
				a[2] += 1
			if st == Plays.AS_MELT and ps != Plays.AS_MELT:
				a[3] += 1
		pst[u] = st if r != Plays.R_BAIT else -1
		a[4 + (st if r != Plays.R_BAIT else 0)] += 1
	if sim.tick % 100 != 0:
		return
	var face := Plays._ps(sim, 1, Plays.PS_AMB_FACE) if Plays.has_mem(sim) else 0
	var fx := FM.cos_a(face)
	var fy := FM.sin_a(face)
	var wx := Plays._ps(sim, 1, Plays.PS_AMB_X) if Plays.has_mem(sim) else 0
	var wy := Plays._ps(sim, 1, Plays.PS_AMB_Y) if Plays.has_mem(sim) else 0
	var ph := Plays._ps(sim, 1, Plays.PS_AMB_PH) if Plays.has_mem(sim) else 0
	print("TR %d t=%ds amb=%d ph=%d men %d/%d" % [sd, sim.tick / 10, Plays._ps(sim, 1, Plays.PS_AMB) if Plays.has_mem(sim) else 0, ph,
		sim.alive_count(0), sim.alive_count(1)])
	for u in sim.n_units:
		if sim.u_state[u] >= 2:
			continue
		var ahead: int = ((sim.u_cx[u] - wx) * fx + (sim.u_cy[u] - wy) * fy) / FM.TRIG_ONE / 1024
		var tg: int = sim.u_target[u] if sim.u_order[u] == 2 else sim.u_ftarget[u]
		if sim.u_side[u] == 1:
			var r := Plays._pm(sim, u, Plays.PU_ROLE) if Plays.has_mem(sim) else 0
			var st := Plays._pm(sim, u, Plays.PU_STATE) if Plays.has_mem(sim) else 0
			var dp: int = Plays._d(sim.u_ax[u] - Plays._pm(sim, u, Plays.PU_X), sim.u_ay[u] - Plays._pm(sim, u, Plays.PU_Y)) / 1024 if r >= Plays.R_HIDE else -1
			print("  N%-2d %-14s r%d s%d st%d post%4dm ahead%4dm hid%d fire%d ord%d tgt%3d lost%3d kills%3d" % [u, UT.key_of(sim.u_otype[u]), r, st,
				sim.u_state[u], dp, -ahead, 1 if sim.hidden_from(u, 0) else 0, sim.u_fire[u], sim.u_order[u], tg, int(n0[u]) - sim.u_alive[u], sim.u_kills[u]])
		else:
			print("  S%-2d %-14s ahead%4dm st%d ord%d tgt%3d lost%3d kills%3d ai%d" % [u, UT.key_of(sim.u_otype[u]), -ahead, sim.u_state[u],
				sim.u_order[u], tg, int(n0[u]) - sim.u_alive[u], sim.u_kills[u], sim.u_ai[u]])
