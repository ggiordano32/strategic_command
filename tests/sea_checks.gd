extends RefCounted
## Sea battle checks (N3a; docs/DESIGN.md "Sea battles (as built, N3a)"),
## shared by tests/determinism_test.gd ("--only=sea", also in the full run),
## tests/lockstep_test.gd ("--only=sea", also in the full run) and
## tests/pack_test.gd (the campaign round trip).
##
## determinism(): the SCENARIOS (a frigate duel, three sloops against a
## galleon, a boarding, upwind and downwind starts, a fight by a coast with
## an island) run twice with identical hashes on every tick, the same from
## snapshots restored at several ticks, a different seed diverges; across
## them broadsides, raking, chain, a boarding and a capture, a
## ship striking, tacking or wearing all happened. A table of each battle
## (time to decide, winner, ships sunk / taken / escaped) is printed.
## sea_room() (sea pass 4): a tack carries her way; lee-coast starts clear
## and the leeward fleet neither grounds nor hangs back.
## flight() (the flight rule, 2026-10-21): a beaten AI fleet flees and its
## ships escape, let go it rallies and holds, a fleet in flight loses on the
## clock, a player's ship ordered to load grape fires it (the battle AI no
## longer loads grape, so grape is not in the AI coverage list).
## douse() (the Douse order, 2026-10-22): a burning frigate with a thin
## crew, an enemy abeam in range: left alone her magazine blows; doused the
## fire is out, her guns silent meanwhile (loaded guns keep their load), the
## order off by itself, the guns firing again after; snapshot / restore
## carry s_douse; refused with no fire and for a fire ship; the battle AI
## douses by its skill (Easy any fire, Average a fire outgrowing her crew,
## Skilled not with a target in arc while the magazine is safe).
## lockstep(): two peers sharing side 0 against the battle AI through the
## lockstep layer (random orders for their own ships and the other's,
## refused alike, through a relay with random delays), every frame's hash
## equal; a third peer restored from a snapshot mid-battle follows; a solo
## run through Lockstep equals the plain sim.
## campaign(): a West campaign with a player: an interception with the
## player's fleet is a pending sea battle; fought in the sea sim, its
## outcome written back (ships lost / taken / damaged, the event), the same
## twice; auto-resolved by the formula; JSON round trips.

const SeaSim := preload("res://sim/sea_sim.gd")
const ST := preload("res://sim/sea_types.gd")
const Lockstep := preload("res://sim/lockstep.gd")

const SCENARIOS: Array[String] = ["frigates", "sloops_galleon", "boarding", "upwind", "downwind", "coast", "melee",
	"fireship", "flight"]


static func scenario(key: String) -> Dictionary:
	var u: Array = []
	var scn := {"sea": 1, "wind_deg": 90, "wind_str": 80, "ai_sides": [1, 1], "layout": "ns", "units": u}
	match key:
		"frigates":
			u.append({"side": 0, "t": "frigate", "q": 112})
			u.append({"side": 1, "t": "frigate", "q": 95, "bq": 115})
		"sloops_galleon":
			for i in 3:
				u.append({"side": 0, "t": "sloop", "q": 92, "bq": 136})
			u.append({"side": 1, "t": "galleon", "q": 95, "bq": 126, "crew": 70})
		"boarding":
			for i in 2:
				u.append({"side": 0, "t": "brigantine", "q": 92, "bq": 140, "troops": 50})
			u.append({"side": 1, "t": "frigate", "crew": 40, "rig": 60})
			scn["wind_deg"] = 60
			scn["layout"] = "gauge0"  # the pirates come down the wind on her
		"upwind":
			u.append({"side": 0, "t": "frigate"})
			u.append({"side": 1, "t": "frigate"})
			scn["layout"] = "gauge0"
		"downwind":
			u.append({"side": 0, "t": "frigate"})
			u.append({"side": 1, "t": "frigate"})
			scn["layout"] = "gauge1"
		"coast":
			u.append({"side": 0, "t": "frigate"})
			u.append({"side": 0, "t": "sloop"})
			u.append({"side": 1, "t": "frigate"})
			u.append({"side": 1, "t": "brigantine"})
			scn["land"] = {"kind": 2, "dirs": (1 << 6) | (1 << 5), "mseed": 77, "ix": 1500, "iy": 900, "ir": 110}
			scn["layout"] = "ns"
			scn["wind_deg"] = 110
		"melee":
			# (N3b) Pirate sloops close aboard a Spanish brigantine: a deck melee.
			u.append({"side": 0, "t": "brigantine", "x": 1080, "y": 980, "head": 0, "q": 92, "bq": 140,
				"ck": "brethren", "troops": 40, "tk": [["cutlass", 70], ["buccaneers", 30]], "cq": 130})
			u.append({"side": 0, "t": "sloop", "x": 1320, "y": 980, "head": 0, "q": 92, "bq": 130, "ck": "brethren"})
			u.append({"side": 1, "t": "brigantine", "x": 1200, "y": 760, "head": 270, "q": 95, "bq": 115, "crew": 60,
				"ck": "new_spain", "troops": 12, "tk": [["musketeers", 100]]})
		"fireship":
			# (N3c) A fire ship with a frigate, upwind of a galleon and a frigate.
			u.append({"side": 0, "t": "frigate", "q": 105})
			u.append({"side": 0, "t": "fire_ship"})
			u.append({"side": 1, "t": "galleon", "q": 95})
			u.append({"side": 1, "t": "frigate", "q": 95})
			scn["layout"] = "gauge0"
		"flight":
			# (The flight rule) Two crack frigates against a frigate and a brigantine: the weaker fleet breaks off.
			u.append({"side": 0, "t": "frigate", "q": 130})
			u.append({"side": 0, "t": "frigate", "q": 130})
			u.append({"side": 1, "t": "frigate", "q": 85})
			u.append({"side": 1, "t": "brigantine", "q": 85})
	return scn


## Run scenario `key` for up to `ticks` (stops 30 ticks after it ends):
## per-tick hashes, the result and the stats. snap_at: ticks at which a copy
## restored from a snapshot runs alongside and must keep the same hash.
static func run(key: String, p_seed: int, ticks: int, snap_at: Array = []) -> Dictionary:
	var scn := scenario(key)
	var sim := SeaSim.new()
	sim.setup(scn, p_seed)
	var hashes := PackedInt64Array()
	var copies: Array = []
	var bad := ""
	var stop := -1
	for t in ticks:
		if snap_at.has(t):
			var cp := SeaSim.new()
			cp.setup(scn, p_seed)
			if not cp.restore(sim.snapshot()):
				bad = "restore failed at tick %d" % t
			elif cp.state_hash() != sim.state_hash():
				bad = "restored hash differs at tick %d" % t
			copies.append(cp)
		sim.step()
		hashes.append(sim.state_hash())
		for cp in copies:
			cp.step()
			if bad == "" and cp.state_hash() != sim.state_hash():
				bad = "a copy restored from a snapshot diverged at tick %d" % sim.tick
		if sim.ended != 0 and stop < 0:
			stop = t + 30
		if stop >= 0 and t >= stop:
			break
	return {"hashes": hashes, "result": sim.result(), "stats": sim.stats.duplicate(), "bad": bad, "sim": sim}


static func _side_text(r: Dictionary, side: int) -> String:
	var sd: Dictionary = r["sides"][side]
	return "%d ships: %d sunk, %d taken, %d escaped" % [int(sd["ships"]), int(sd["sunk"]), int(sd["taken"]), int(sd["fled"])]


## Returns the number of failures (printed with "FAIL").
static func determinism() -> int:
	var fails := 0
	var cover := {}
	var table: Array[String] = ["| Battle | Decided | Winner | Side 0 | Side 1 | Broadsides | Boardings |",
		"|---|---|---|---|---|---|---|"]
	for key in SCENARIOS:
		var a := run(key, 4242, 9200, [400, 1200, 2500])
		var b := run(key, 4242, 9200)
		var ha: PackedInt64Array = a["hashes"]
		var hb: PackedInt64Array = b["hashes"]
		if ha != hb:
			fails += 1
			var at := -1
			for t in mini(ha.size(), hb.size()):
				if ha[t] != hb[t]:
					at = t
					break
			printerr("FAIL sea %s: the same seed diverged at tick %d" % [key, at])
		else:
			print("PASS sea %s: %d ticks identical, final hash %08x" % [key, ha.size(), ha[ha.size() - 1]])
		if str(a["bad"]) != "":
			fails += 1
			printerr("FAIL sea %s: %s" % [key, a["bad"]])
		else:
			print("PASS sea %s: snapshots restored at 400, 1200, 2500 run on identically" % key)
		var c := run(key, 999, 600)
		var hc: PackedInt64Array = c["hashes"]
		var div := -1
		for t in mini(ha.size(), hc.size()):
			if ha[t] != hc[t]:
				div = t
				break
		if div < 0:
			fails += 1
			printerr("FAIL sea %s: a different seed did not diverge" % key)
		var r: Dictionary = a["result"]
		var stt: Dictionary = a["stats"]
		for k in stt:
			cover[k] = int(cover.get(k, 0)) + int(stt[k])
		var dt := int(r["decided_tick"])
		table.append("| %s | %s | %s | %s | %s | %d | %d (%d taken) |" % [key,
			("%d:%02d" % [dt / 600, (dt / 10) % 60]) if dt >= 0 else "no", "side %d" % int(r["winner"]),
			_side_text(r, 0), _side_text(r, 1), int(stt["broadsides"]), int(stt["boardings"]), int(stt["captured"])])
		if dt < 0:
			fails += 1
			printerr("FAIL sea %s: not decided in 15 minutes" % key)
	# (Sea pass 4) Chain and grape are choices a ship makes close in, so a
	# single seed may not show them: count them over a few more seeds too.
	for sd in range(1, 5):
		for key in ["frigates", "sloops_galleon", "boarding"]:
			var cs: Dictionary = run(key, sd, 9200)["stats"]
			for k in ["chain", "grape"]:
				cover[k] = int(cover.get(k, 0)) + int(cs[k])
	for k in ["broadsides", "rakes", "chain", "boardings", "captured", "struck", "deck_fights", "deck_taken",
			"deck_shots", "fireships"]:
		if int(cover.get(k, 0)) <= 0:
			fails += 1
			printerr("FAIL sea coverage: no %s in any battle" % k)
	# (N3c) Fire ships over several seeds: some reach their mark and set it
	# alight (and a magazine goes up somewhere).
	var reach := 0
	var blasts := 0
	var lit := 0
	for sd in range(1, 9):
		var fr := run("fireship", sd, 9200)
		var fst: Dictionary = fr["stats"]
		lit += int(fst["fireships"])
		reach += 1 if int(fst["fire_contacts"]) > 0 else 0
		blasts += int(fst["blown"])
	if lit < 8 or reach <= 0 or blasts <= 0:
		fails += 1
		printerr("FAIL sea fire ships: lit %d of 8, reached the mark %d, magazines %d" % [lit, reach, blasts])
	else:
		print("PASS sea fire ships over 8 seeds: lit %d, reached and fired the mark in %d, magazines blown %d" % [lit, reach, blasts])
	if int(cover.get("tacks", 0)) + int(cover.get("wears", 0)) <= 0:
		fails += 1
		printerr("FAIL sea coverage: nobody tacked or wore")
	print("sea coverage: ", cover)
	for line in table:
		print(line)
	fails += sea_room()
	fails += flight()
	fails += douse()
	return fails


## (Sea pass 4) The leeward fleet: a frigate turning through the wind
## carries her way round (a tack, not a wear); fleets start clear of
## shoals (START_CLEAR_M) and the leeward fleet with LEE_ROOM_M of clear
## water to leeward and on both beams, a lee coast and an island in the
## way; the leeward fleet runs aground at most once over the set and fires
## within four minutes in each (the battle AI both sides).
static func sea_room() -> int:
	var fails := 0
	var t := SeaSim.new()
	t.setup({"sea": 1, "wind_deg": 90, "wind_str": 80, "ai_sides": [0, 0],
		"units": [{"side": 0, "t": "frigate", "x": 800, "y": 900, "head": 20}, {"side": 1, "t": "sloop", "x": 2200, "y": 150}]}, 5)
	t.queue_order({"type": SeaSim.O_SAILS, "unit": 0, "on": 2, "tick": 0})
	for i in 60:
		t.step()
	t.queue_order({"type": SeaSim.O_HEAD, "unit": 0, "facing": SeaSim.bearing_to_angle(160)})
	var slow := 1 << 30
	for i in 400:
		t.step()
		slow = mini(slow, t.s_spd[0])
	var hb := SeaSim.angle_to_bearing(t.heading(0))
	if int(t.stats["tacks"]) != 1 or int(t.stats["wears"]) != 0 or absi(hb - 160) > 3:
		fails += 1
		printerr("FAIL sea tack: tacks %d wears %d, heading %d (wanted 160)" % [int(t.stats["tacks"]), int(t.stats["wears"]), hb])
	else:
		print("PASS sea tack: a frigate tacks through the wind to 160, slowest %d %% of her top speed" % [
			slow * 100 / maxi(t._vmax(0), 1)])
	var lee_ground := 0
	var lines: Array[String] = []
	for k in 6:
		var scn := {"sea": 1, "wind_deg": 80 + k * 4, "wind_str": 70, "ai_sides": [1, 1], "layout": "we" if k % 2 == 0 else "gauge1",
			"land": {"kind": 2, "dirs": (1 << 4) | ((1 << 3) if k >= 3 else 0), "mseed": 101 + k * 37, "ix": 1500, "iy": 400 + k * 80, "ir": 100},
			"units": [{"side": 0, "t": "frigate"}, {"side": 0, "t": "sloop"}, {"side": 1, "t": "frigate"}, {"side": 1, "t": "sloop"}]}
		var sim := SeaSim.new()
		sim.setup(scn, 300 + k)
		var bad := ""
		var r := SeaSim.START_CLEAR_M / SeaSim.CELL_M
		for s in sim.n_units:
			var gx0 := sim.s_x[s] / (SeaSim.CELL_M * SeaSim.U)
			var gy0 := sim.s_y[s] / (SeaSim.CELL_M * SeaSim.U)
			for gy in range(maxi(gy0 - r, 0), mini(gy0 + r + 1, sim.g_h)):
				for gx in range(maxi(gx0 - r, 0), mini(gx0 + r + 1, sim.g_w)):
					if (gx - gx0) * (gx - gx0) + (gy - gy0) * (gy - gy0) <= r * r and sim.g[gy * sim.g_w + gx] == 1:
						bad = "a shoal within %d m of ship %d's start" % [SeaSim.START_CLEAR_M, s]
			if sim.u_side[s] == 0 and sim._start_bad([s], true) > 0:
				bad = "land in the leeward ship %d's sea room" % s
		var first := -1
		var seen := 0
		for i in 9000:
			sim.step()
			while seen < sim.ev_n:
				var e := seen % SeaSim.EV_CAP
				seen += 1
				var a := sim.ev_a[e]
				if sim.ev_k[e] == SeaSim.EV_GROUND and sim.u_side[a] == 0:
					lee_ground += 1
				elif sim.ev_k[e] == SeaSim.EV_BROADSIDE and sim.u_side[a] == 0 and first < 0:
					first = sim.ev_t[e]
			if sim.decided_tick >= 0 or (first >= 0 and i > first + 600):
				break
		if bad == "" and (first < 0 or first > 2400):
			bad = "the leeward fleet's first broadside at tick %d" % first
		if bad != "":
			fails += 1
			printerr("FAIL sea room %d (%s): %s" % [k, str(scn["layout"]), bad])
		else:
			lines.append("%d:%02d" % [first / 600, (first / 10) % 60])
	if lee_ground > 1:
		fails += 1
		printerr("FAIL sea room: the leeward fleet ran aground %d times" % lee_ground)
	elif fails == 0:
		print("PASS sea room: six lee-coast starts clear, the leeward fleet's first broadsides %s, aground %d" % [
			", ".join(PackedStringArray(lines)), lee_ground])
	return fails


## (The flight rule, 2026-10-21) A beaten AI fleet breaks off and runs for
## the edge (its ships escape, the other side holds the field); pursued by
## nobody it rallies after a minute and holds; a fleet in flight does not win
## on the clock; a player's ship ordered to load grape fires it (the battle
## AI no longer loads grape).
static func flight() -> int:
	var fails := 0
	# Flight and escape (the "flight" scenario, AI both sides).
	var esc := 0
	var fled := 0
	var won := 0
	# (8 seeds since the Douse, 2026-10-22: over seeds 1-4 two escapes came from the companion of a ship
	# whose magazine blew; doused, that ship survives to strike and both are taken. Seeds 1-16: 10 escapes
	# before, 8 after, the flight and the wins unchanged.)
	for sd in range(1, 9):
		var sim: SeaSim = run("flight", sd, 9200)["sim"]
		fled += 1 if sim.stat_fl[0] > 0 and sim.fl_t[1] >= 0 else 0
		won += 1 if sim.winner == 0 else 0
		for s in sim.n_units:
			if sim.u_side[s] == 1 and sim.u_state[s] == SeaSim.S_FLED:
				esc += 1
	if fled < 6 or esc < 4 or won < 6:
		fails += 1
		printerr("FAIL sea flight: the beaten fleet fled in %d of 8, ships escaped %d, the stronger held the field %d" % [fled, esc, won])
	else:
		print("PASS sea flight: the beaten fleet fled in %d of 8, %d ships escaped, the stronger held the field %d" % [fled, esc, won])
	# Rally: the AI (side 1) flees, the player (side 0) heaves to and lets it go.
	var rallied := 0
	var held := 0
	for sd in range(1, 5):
		var scn := scenario("flight")
		scn["ai_sides"] = [0, 1]
		var sim := SeaSim.new()
		sim.setup(scn, sd)
		var stopped := false
		for i in 6000:
			if not stopped:
				for s in 2:
					if sim.u_state[s] == SeaSim.S_SAIL and (sim.s_mode[s] == SeaSim.M_FREE or i % 300 == 0):
						var t := 2 if sim.u_state[2] == SeaSim.S_SAIL else 3
						sim.queue_order({"type": SeaSim.O_TARGET, "unit": s, "target": t})
			if sim.fl_on[1] == 1 and not stopped:
				stopped = true
				for s in 2:
					sim.queue_order({"type": SeaSim.O_HOLD, "unit": s})
					sim.queue_order({"type": SeaSim.O_SAILS, "unit": s, "on": 0})
			sim.step()
			if sim.fl_on[1] == 2:
				rallied += 1
				var ok := true
				for s in sim.n_units:
					if sim.u_side[s] == 1 and sim.u_state[s] == SeaSim.S_SAIL and sim.s_mode[s] == SeaSim.M_FLEE \
							and sim.s_ffl[s] != 0:
						ok = false
				held += 1 if ok else 0
				break
			if sim.decided_tick >= 0:
				break
	if rallied < 2 or held != rallied:
		fails += 1
		printerr("FAIL sea flight rally: rallied in %d of 4, holding %d" % [rallied, held])
	else:
		print("PASS sea flight rally: let go, the fleet rallied and held in %d of 4" % rallied)
	# The clock: a fleet in flight does not hold the field, whatever its power.
	var c := SeaSim.new()
	var cs := scenario("flight")
	cs["time_limit"] = 30
	c.setup(cs, 3)
	c.fl_on[0] = 1
	c.fl_t[0] = 0
	for i in 301:
		c.step()
		if c.decided_tick >= 0:
			break
	if c.winner != 1 or c.stat_fl[3] != 1:
		fails += 1
		printerr("FAIL sea flight clock: winner %d (the fleeing side 0 kept the field?)" % c.winner)
	else:
		print("PASS sea flight clock: at the time limit the fleet in flight loses the field")
	# Grape by a player's order.
	var gscn := scenario("frigates")
	gscn["ai_sides"] = [0, 1]
	var g := SeaSim.new()
	g.setup(gscn, 11)
	g.queue_order({"type": SeaSim.O_SHOT, "unit": 0, "on": ST.SHOT_GRAPE, "tick": 0})
	g.queue_order({"type": SeaSim.O_TARGET, "unit": 0, "target": 1, "tick": 0})
	for i in 6000:
		g.step()
		if int(g.stats["grape"]) > 0 or g.decided_tick >= 0:
			break
	if int(g.stats["grape"]) <= 0:
		fails += 1
		printerr("FAIL sea grape: a frigate ordered to load grape never fired it")
	else:
		print("PASS sea grape: a frigate ordered to load grape fires it")
	return fails


## The douse scene: a frigate (side 0, crew `crew` %) burning at `burn`,
## an enemy frigate abeam to starboard 120 m off holding her fire, no AI
## unless `ai` (then side 0's skill `skill`).
static func _douse_sim(crew: int, burn: int, ai: int = 0, skill: int = 1) -> SeaSim:
	var sim := SeaSim.new()
	sim.setup({"sea": 1, "wind_deg": 0, "wind_str": 60, "ai_sides": [ai, 0], "ai_skill": [skill, 1], "units": [
		{"side": 0, "t": "frigate", "x": 1000, "y": 800, "head": 0, "crew": crew},
		{"side": 1, "t": "frigate", "x": 1120, "y": 800, "head": 0},
		{"side": 0, "t": "fire_ship", "x": 300, "y": 300, "head": 0}]}, 21)
	sim.queue_order({"type": SeaSim.O_FIRE, "unit": 1, "on": 0, "tick": 0})
	sim.queue_order({"type": SeaSim.O_SAILS, "unit": 0, "on": 0, "tick": 0})
	sim.queue_order({"type": SeaSim.O_SAILS, "unit": 1, "on": 0, "tick": 0})
	sim.s_burn[0] = burn
	return sim


## Broadsides fired by ship s among the events seen since `seen` (returns
## [count, new seen]).
static func _fired(sim: SeaSim, s: int, seen: int) -> Array:
	var n := 0
	while seen < sim.ev_n:
		var i := seen % SeaSim.EV_CAP
		seen += 1
		if sim.ev_k[i] == SeaSim.EV_BROADSIDE and sim.ev_a[i] == s:
			n += 1
	return [n, seen]


static func douse() -> int:
	var fails := 0
	# Left alone: the thin crew lose the race and the magazine blows.
	var a := _douse_sim(55, 200)
	var blew := -1
	var fired_a := 0
	var seen := 0
	for t in 6000:
		a.step()
		var fr := _fired(a, 0, seen)
		fired_a += int(fr[0])
		seen = int(fr[1])
		if a.s_blown[0] != 0 or a.u_state[0] == SeaSim.S_SUNK:
			blew = a.tick if a.s_blown[0] != 0 else -2
			break
	# Doused from tick 0: out at tick U, the guns silent meanwhile.
	var b := _douse_sim(55, 200)
	b.queue_order({"type": SeaSim.O_DOUSE, "unit": 0, "on": 1, "tick": 0})
	b.queue_order({"type": SeaSim.O_DOUSE, "unit": 1, "on": 1, "tick": 0})   # no fire: refused
	b.queue_order({"type": SeaSim.O_DOUSE, "unit": 2, "on": 1, "tick": 0})   # a fire ship: refused
	var out_t := -1
	var fired_on := 0
	var fired_after := 0
	var ld0 := -1
	var snap_ok := ""
	var copy: SeaSim = null
	seen = 0
	for t in 1500:
		b.step()
		if b.tick == 2:
			ld0 = b.s_rl[0] + b.s_rl[1]
		if b.tick == 40 and b.s_douse[0] != 0:
			copy = SeaSim.new()
			copy.setup({"sea": 1, "wind_deg": 0, "wind_str": 60, "ai_sides": [0, 0], "ai_skill": [1, 1], "units": [
				{"side": 0, "t": "frigate", "x": 1000, "y": 800, "head": 0, "crew": 55},
				{"side": 1, "t": "frigate", "x": 1120, "y": 800, "head": 0},
				{"side": 0, "t": "fire_ship", "x": 300, "y": 300, "head": 0}]}, 21)
			if not copy.restore(b.snapshot()) or copy.s_douse[0] != 1 or copy.state_hash() != b.state_hash():
				snap_ok = "the snapshot at tick 40 did not carry s_douse"
				copy = null
		elif copy != null:
			copy.step()
			if snap_ok == "" and copy.state_hash() != b.state_hash():
				snap_ok = "the restored copy diverged at tick %d" % b.tick
		var fr2 := _fired(b, 0, seen)
		seen = int(fr2[1])
		if out_t < 0:
			fired_on += int(fr2[0])
			if b.s_burn[0] == 0:
				out_t = b.tick
				if b.s_douse[0] != 0:
					snap_ok = "s_douse still on with the fire out"
				if b.s_rl[0] + b.s_rl[1] != ld0:
					snap_ok = "the guns reloaded while dousing (%d -> %d)" % [ld0, b.s_rl[0] + b.s_rl[1]]
		else:
			fired_after += int(fr2[0])
			if fired_after > 0 and b.tick > out_t + 200:
				break
	var refused := b.s_douse[1] == 0 and b.s_douse[2] == 0 and int(b.stats["douse"]) == 1
	if blew <= 0 or fired_a <= 0 or out_t < 0 or fired_on != 0 or fired_after <= 0 or snap_ok != "" or not refused:
		fails += 1
		printerr("FAIL sea douse: left alone blew at %d (fired %d); doused out at %d, fired meanwhile %d, after %d; %s; refused %s" % [
			blew, fired_a, out_t, fired_on, fired_after, snap_ok, refused])
	else:
		print("PASS sea douse: a frigate at 55 %% crew burning 200, left alone, fires %d broadsides and her magazine blows at tick %d; doused, the fire is out at tick %d with the guns silent (none fired, the reload held) and the order off by itself, she fires %d after; a snapshot mid-douse carries it; refused with no fire and for a fire ship" % [
			fired_a, blew, out_t, fired_after])
	# The battle AI by skill: thin crew (losing the race) and a full one.
	var res: Array[String] = []
	var want := {"easy full": 1, "average full": 0, "average thin": 1, "skilled thin arc": 0, "skilled thin hot": 1}
	var cases := [["easy full", 0, 100, 100], ["average full", 1, 100, 100], ["average thin", 1, 55, 100],
		["skilled thin arc", 2, 55, 100], ["skilled thin hot", 2, 55, 400]]
	var got := {}
	for c in cases:
		var sim := _douse_sim(int(c[2]), int(c[3]), 1, int(c[1]))
		var on := 0
		for t in 40:
			sim.step()
			on = maxi(on, sim.s_douse[0])
		got[str(c[0])] = on
		res.append("%s %d" % [str(c[0]), on])
	if got != want:
		fails += 1
		printerr("FAIL sea douse AI: ", ", ".join(res))
	else:
		print("PASS sea douse AI (douses within 4 s): ", ", ".join(res))
	return fails


# --------------------------------------------------------------- lockstep ---

class Peer:
	extends RefCounted
	var ls
	var me := 0
	var n := 0
	var hashes := {}
	var rng := 0


static func _rnd(p: Peer, m: int) -> int:
	p.rng = (p.rng * 1103515245 + 12345) & 0x7FFFFFFF
	return (p.rng >> 4) % maxi(m, 1)


static func _orders(p: Peer, frame: int) -> Array:
	var out: Array = []
	var sim = p.ls.sim
	if _rnd(p, 100) >= 7:
		return out
	var u: int = _rnd(p, sim.n_units)
	if sim.u_side[u] != 0:
		return out
	var f := frame
	match _rnd(p, 8):
		0, 1:
			out.append({"f": f, "type": SeaSim.O_SAIL, "unit": u, "x": 300 + _rnd(p, 1800), "y": 200 + _rnd(p, 1200)})
		2:
			for t in sim.n_units:
				if sim.u_side[t] == 1:
					out.append({"f": f, "type": SeaSim.O_TARGET, "unit": u, "target": t})
					break
		3:
			out.append({"f": f, "type": SeaSim.O_SAILS, "unit": u, "on": _rnd(p, 3)})
		4:
			out.append({"f": f, "type": SeaSim.O_SHOT, "unit": u, "on": _rnd(p, 3)})
		5:
			for t in sim.n_units:
				if sim.u_side[t] == 1:
					out.append({"f": f, "type": SeaSim.O_BOARD, "unit": u, "target": t})
		6:
			out.append({"f": f, "type": SeaSim.O_HEAD, "unit": u, "facing": _rnd(p, 1024)})
		_:
			out.append({"f": f, "type": SeaSim.O_FIRE, "unit": u, "on": _rnd(p, 2)})
	return out


static func lockstep() -> int:
	var fails := 0
	var scn := scenario("coast")
	scn["ai_sides"] = [0, 1]
	var home: Array = []
	var k := 0
	for d in scn["units"]:
		if int(d["side"]) == 0:
			home.append(k % 2)
			k += 1
		else:
			home.append(-1)
	const LEAD := 3
	var peers: Array = []
	for i in 2:
		var p := Peer.new()
		p.ls = Lockstep.new()
		p.ls.setup(scn, 777, home, [0, 1], 0)
		p.me = i
		p.rng = 99 + i * 31
		peers.append(p)
	var sent: Array = [[], []]     # every message a player sent, in order
	var inbox: Array = []         # [deliver at loop step, to peer, msg]
	var relay := 12345
	var fifo := [0, 0, 0]
	var observer: Peer = null
	var obs_from := -1
	var refused := 0
	for step in 1600:
		for p: Peer in peers:
			var fr: int = p.ls.frame + LEAD
			p.n += 1
			var msg := {"p": p.me, "n": p.n, "k": fr, "o": _orders(p, fr)}
			if _rnd(p, 50) == 0:
				# An order for the other player's ship: refused on every peer.
				for u in p.ls.sim.n_units:
					if home[u] == 1 - p.me:
						(msg["o"] as Array).append({"f": fr, "type": SeaSim.O_SAILS, "unit": u, "on": 0})
						break
			(sent[p.me] as Array).append(msg)
			p.ls.receive(msg)
			relay = (relay * 1103515245 + 12345) & 0x7FFFFFFF
			# (FIFO per receiver, as the relay is)
			fifo[1 - p.me] = maxi(int(fifo[1 - p.me]), step + 1 + (relay >> 8) % 3)
			inbox.append([int(fifo[1 - p.me]), 1 - p.me, msg])
			if observer != null:
				fifo[2] = maxi(int(fifo[2]), step + 1 + (relay >> 9) % 2)
				inbox.append([int(fifo[2]), 2, msg])
		var rest: Array = []
		for it in inbox:
			if int(it[0]) > step:
				rest.append(it)
				continue
			var to := int(it[1])
			var q: Peer = observer if to == 2 else peers[to]
			if q != null:
				q.ls.receive(it[2])
		inbox = rest
		for p in peers + ([observer] if observer != null else []):
			while (p as Peer).ls.can_advance():
				(p as Peer).ls.advance()
				(p as Peer).hashes[(p as Peer).ls.frame] = (p as Peer).ls.state_hash()
		if step == 700:
			# A third peer joins: A's snapshot plus every message sent so far.
			observer = Peer.new()
			observer.me = 2
			observer.ls = Lockstep.new()
			observer.ls.setup(scn, 777, home, [0, 1], 0)
			if not observer.ls.restore((peers[0] as Peer).ls.snapshot()):
				fails += 1
				printerr("FAIL sea lockstep: the observer could not restore A's snapshot")
			obs_from = observer.ls.frame
			for pl in 2:
				for m in sent[pl]:
					observer.ls.receive(m)
	var a: Peer = peers[0]
	var b: Peer = peers[1]
	var n_cmp := 0
	for f in a.hashes:
		if b.hashes.has(f):
			n_cmp += 1
			if int(a.hashes[f]) != int(b.hashes[f]):
				fails += 1
				printerr("FAIL sea lockstep: the peers differ at frame %d" % int(f))
				break
	var n_obs := 0
	for f in observer.hashes:
		if a.hashes.has(f) and int(f) > obs_from:
			n_obs += 1
			if int(a.hashes[f]) != int(observer.hashes[f]):
				fails += 1
				printerr("FAIL sea lockstep: the observer differs at frame %d" % int(f))
				break
	refused = int(a.ls.rejected)
	var sim = a.ls.sim
	if n_cmp < 1200 or n_obs < 500:
		fails += 1
		printerr("FAIL sea lockstep: too few frames compared (%d, observer %d)" % [n_cmp, n_obs])
	elif refused <= 0 or refused != int(b.ls.rejected):
		fails += 1
		printerr("FAIL sea lockstep: orders for the other's ship refused %d / %d" % [refused, int(b.ls.rejected)])
	else:
		print("PASS sea lockstep: two peers equal on %d frames, the observer from frame %d on %d; %d foreign orders refused alike; %d broadsides" % [
			n_cmp, obs_from, n_obs, refused, int(sim.stats["broadsides"])])
	# Solo through Lockstep equals the plain sim.
	var plain := SeaSim.new()
	plain.setup(scn, 31)
	var home0: Array = []
	for d in scn["units"]:
		home0.append(0 if int(d["side"]) == 0 else -1)
	var ls := Lockstep.new()
	ls.setup(scn, 31, home0, [0], 0)
	var bad := -1
	for t in 900:
		var os: Array = []
		if t % 61 == 7:
			for u in plain.n_units:
				if plain.u_side[u] == 0:
					var o := {"tick": plain.tick, "type": SeaSim.O_SAIL, "unit": u, "x": 400 + t % 900, "y": 300 + t % 700,
						"player": 0, "seq": (t + 1) * 64 + os.size()}
					plain.queue_order(o)
					var lo := o.duplicate()
					lo.erase("tick")
					lo.erase("player")
					lo.erase("seq")
					lo["f"] = ls.frame
					os.append(lo)
		ls.receive({"p": 0, "n": t + 1, "k": ls.frame, "o": os})
		ls.advance()
		plain.step()
		if ls.sim.state_hash() != plain.state_hash():
			bad = t
			break
	if bad >= 0:
		fails += 1
		printerr("FAIL sea: solo through lockstep differs from the plain sim at tick %d" % bad)
	else:
		print("PASS sea: solo through lockstep equals the plain sim (900 ticks)")
	fails += lockstep_douse()
	return fails


## (The Douse order) Two peers: player 1's frigate burns (set alike on both
## after setup), player 0 orders her doused (not his ship: refused alike),
## player 1 does at frame 3; every frame's hash equal, s_douse on on both,
## the hash differs from a run without the order; a third peer restored
## from player 0's snapshot mid-douse follows to the fire's end.
static func lockstep_douse() -> int:
	var scn := {"sea": 1, "wind_deg": 0, "wind_str": 60, "ai_sides": [0, 1], "units": [
		{"side": 0, "t": "frigate", "x": 1000, "y": 800, "head": 0, "crew": 55},
		{"side": 0, "t": "sloop", "x": 700, "y": 800, "head": 0},
		{"side": 1, "t": "frigate", "x": 1400, "y": 300, "head": 180}]}
	var home := [1, 0, -1]
	var peers: Array = []
	for i in 3:
		var ls := Lockstep.new()
		ls.setup(scn, 55, home, [0, 1], 0)
		ls.sim.s_burn[0] = 200
		peers.append(ls)
	var ctl: Lockstep = peers[2]   # no douse order: the control
	var msgs: Array = []
	var joiner: Lockstep = null
	var bad := ""
	var on_frames := 0
	for f in 900:
		var o0: Array = []
		var o1: Array = []
		if f == 2:
			o0.append({"f": f + 1, "type": SeaSim.O_DOUSE, "unit": 0, "on": 1})
		if f == 2:
			o1.append({"f": f + 1, "type": SeaSim.O_DOUSE, "unit": 0, "on": 1})
		var m0 := {"p": 0, "n": f + 1, "k": f + 1, "o": o0}
		var m1 := {"p": 1, "n": f + 1, "k": f + 1, "o": o1}
		msgs.append(m0)
		msgs.append(m1)
		for k in 2:
			(peers[k] as Lockstep).receive(m0)
			(peers[k] as Lockstep).receive(m1)
		ctl.receive({"p": 0, "n": f + 1, "k": f + 1, "o": []})
		ctl.receive({"p": 1, "n": f + 1, "k": f + 1, "o": []})
		if joiner != null:
			joiner.receive(m0)
			joiner.receive(m1)
		for ls in peers + ([joiner] if joiner != null else []):
			while (ls as Lockstep).can_advance():
				(ls as Lockstep).advance()
		var a: Lockstep = peers[0]
		var b: Lockstep = peers[1]
		if bad == "" and a.state_hash() != b.state_hash():
			bad = "the peers differ at frame %d" % a.frame
		if bad == "" and joiner != null and joiner.frame == a.frame and joiner.state_hash() != a.state_hash():
			bad = "the joiner differs at frame %d" % a.frame
		if a.sim.s_douse[0] != 0:
			on_frames += 1
			if joiner == null and on_frames == 30:
				joiner = Lockstep.new()
				joiner.setup(scn, 55, home, [0, 1], 0)
				if not joiner.restore(a.snapshot()) or joiner.sim.s_douse[0] != 1:
					bad = "the joiner's snapshot did not carry s_douse"
		if a.sim.s_burn[0] == 0 and on_frames > 0 and joiner != null:
			break
	var a2: Lockstep = peers[0]
	var b2: Lockstep = peers[1]
	if bad != "" or on_frames <= 0 or a2.sim.s_douse[0] != 0 or a2.sim.s_burn[0] != 0 or a2.rejected != 1 or b2.rejected != 1 \
			or ctl.state_hash() == a2.state_hash():
		printerr("FAIL sea lockstep douse: %s; dousing %d frames, refused %d / %d, burn at the end %d" % [bad, on_frames,
			a2.rejected, b2.rejected, a2.sim.s_burn[0]])
		return 1
	print("PASS sea lockstep douse: player 1's order from the peer applied alike (dousing %d frames, the fire out at frame %d), player 0's for her refused on both, a joiner restored mid-douse follows; the control without it differs" % [
		on_frames, a2.frame])
	return 0


## Live co-op at sea (milestone 5 at sea): two players on side 0 (player 0
## a pirate brigantine, player 1 a sloop and a fire ship) against the battle
## AI, through the lockstep with a relay of random delays; scripted: player
## 0 boards (a deck melee), player 1 sends the fire ship in, player 1 gives
## the sloop to player 0 (player 0 then orders it; player 1's order for it
## is refused on every peer), a pause vote (asked, accepted; resumed), a
## speed vote (4x), player 1 dropped by the relay (their ships to player 0)
## and admitted again by the host (their ships back); a joiner restores
## from player 0's snapshot mid-battle and follows. Every frame's hash equal
## on all three. Returns failures.
static func lockstep_coop() -> int:
	var fails := 0
	var scn := {"sea": 1, "wind_deg": 90, "wind_str": 80, "ai_sides": [0, 1], "layout": "ns", "units": [
		{"side": 0, "t": "brigantine", "x": 1000, "y": 1000, "head": 0, "q": 92, "bq": 140, "troops": 40, "ck": "brethren",
			"tk": [["cutlass", 70], ["buccaneers", 30]], "cq": 120},
		{"side": 0, "t": "sloop", "x": 1300, "y": 1060, "head": 0, "ck": "brethren", "bq": 130},
		{"side": 0, "t": "fire_ship", "x": 1450, "y": 900, "head": 270, "ck": "brethren"},
		# (Her rigging shot through: she is caught. Since sea pass 4 a ship
		# turning off the wind carries her way, so a sound one runs.)
		{"side": 1, "t": "brigantine", "x": 1040, "y": 860, "head": 90, "crew": 60, "rig": 30, "troops": 10,
			"ck": "new_spain", "tk": [["musketeers", 100]]},
		{"side": 1, "t": "frigate", "x": 900, "y": 560, "head": 180, "ck": "new_spain"},
		{"side": 1, "t": "galleon", "x": 700, "y": 400, "head": 180, "ck": "new_spain"}]}
	var home := [0, 1, 1, -1, -1, -1]
	const LEAD := 3
	var peers: Array = []
	for i in 2:
		var p := Peer.new()
		p.ls = Lockstep.new()
		p.ls.setup(scn, 4243, home, [0, 1], 0)
		p.me = i
		p.rng = 7 + i * 13
		peers.append(p)
	var a: Peer = peers[0]
	var b: Peer = peers[1]
	var sent: Array = []          # every stream item in relay order: ["in", msg] / ["drop", ev]
	var inbox: Array = []
	var relay := 777
	var fifo := [0, 0, 0]
	var joiner: Peer = null
	var join_from := -1
	var seen := {"gift_at": -1, "sloop_ordered": -1, "pause_on": -1, "resume_on": -1, "speed_on": -1, "drop_at": -1,
		"took": -1, "admit_at": -1, "back": -1}
	var asked := {}
	var drop_s := 0
	for step in 2600:
		for p: Peer in peers:
			var fr: int = p.ls.frame + LEAD
			p.n += 1
			var os: Array = []
			var ls = p.ls
			var f0: int = ls.frame
			if p.me == 0:
				if f0 >= 2 and not asked.has("board"):
					asked["board"] = f0
					os.append({"f": fr, "type": SeaSim.O_BOARD, "unit": 0, "target": 3})
				if ls.u_cmd[1] == 0 and seen["sloop_ordered"] < 0:
					seen["sloop_ordered"] = f0
					os.append({"f": fr, "type": SeaSim.O_SAIL, "unit": 1, "x": 700, "y": 900})
				if f0 >= 150 and not asked.has("pause"):
					asked["pause"] = f0
					os.append({"f": fr, "type": Lockstep.C_PAUSE, "want": 1})
				if int(seen["pause_on"]) >= 0 and f0 >= int(seen["pause_on"]) + 20 and not asked.has("resume"):
					asked["resume"] = f0
					os.append({"f": fr, "type": Lockstep.C_PAUSE, "want": 0})
				if ls.vote_speed_by == 1 and not asked.has("speed_yes"):
					asked["speed_yes"] = f0
					os.append({"f": fr, "type": Lockstep.C_ANSWER, "what": 1, "yes": 1})
				if int(seen["took"]) >= 0 and f0 >= int(seen["took"]) + 40 and not asked.has("admit"):
					asked["admit"] = f0
					os.append({"f": maxi(fr, int(ls.drop_at.get(1, 0))), "type": Lockstep.C_ADMIT, "who": 1, "keep": 0})
			else:
				if f0 >= 2 and not asked.has("fire"):
					asked["fire"] = f0
					os.append({"f": fr, "type": SeaSim.O_TARGET, "unit": 2, "target": 4})
				if f0 >= 40 and not asked.has("gift"):
					asked["gift"] = f0
					os.append({"f": fr, "type": Lockstep.C_GIFT, "unit": 1, "to": 0})
				if f0 >= 60 and not asked.has("foreign"):
					asked["foreign"] = f0
					os.append({"f": fr, "type": SeaSim.O_SAILS, "unit": 1, "on": 0})  # (no longer theirs: refused)
				if ls.vote_pause_by == 0 and ls.vote_of(0, 1) == 0 and not asked.has("pause_yes_%d" % ls.vote_pause_want):
					asked["pause_yes_%d" % ls.vote_pause_want] = f0
					os.append({"f": fr, "type": Lockstep.C_ANSWER, "what": 0, "yes": 1})
				if f0 >= 250 and int(seen["resume_on"]) >= 0 and not asked.has("speed"):
					asked["speed"] = f0
					os.append({"f": fr, "type": Lockstep.C_SPEED, "q": 16})
			var msg := {"p": p.me, "n": p.n, "k": fr, "o": os}
			p.ls.receive(msg)
			sent.append(["in", msg])
			relay = (relay * 1103515245 + 12345) & 0x7FFFFFFF
			fifo[1 - p.me] = maxi(int(fifo[1 - p.me]), step + 1 + (relay >> 8) % 3)
			inbox.append([int(fifo[1 - p.me]), 1 - p.me, ["in", msg]])
			if joiner != null:
				fifo[2] = maxi(int(fifo[2]), step + 1 + (relay >> 9) % 2)
				inbox.append([int(fifo[2]), 2, ["in", msg]])
		# The relay drops player 1 once frame 300 is passed (after B's last mark).
		if drop_s == 0 and a.ls.frame >= 300:
			drop_s = 1
			var ev := {"s": 1, "t": "drop", "who": 1, "after": int(b.ls.marks.get(1, 0)), "to": 0}
			sent.append(["drop", ev])
			for q in [0, 1, 2]:
				fifo[q] = maxi(int(fifo[q]), step + 1)
				if q < 2 or joiner != null:
					inbox.append([int(fifo[q]), q, ["drop", ev]])
		var rest: Array = []
		for it in inbox:
			if int(it[0]) > step:
				rest.append(it)
				continue
			var to := int(it[1])
			var q: Peer = joiner if to == 2 else peers[to]
			if q == null:
				continue
			var item: Array = it[2]
			if str(item[0]) == "in":
				q.ls.receive(item[1])
			else:
				q.ls.receive_event(item[1])
				q.ls.saw(1)
		inbox = rest
		for p in peers + ([joiner] if joiner != null else []):
			var pp := p as Peer
			while pp.ls.can_advance():
				pp.ls.advance()
				pp.hashes[pp.ls.frame] = pp.ls.state_hash()
		# Note what happened (player 0's view; the others are compared by hash).
		var la = a.ls
		if la.u_cmd[1] == 0 and int(seen["gift_at"]) < 0:
			seen["gift_at"] = la.frame
		if la.paused == 1 and int(seen["pause_on"]) < 0:
			seen["pause_on"] = la.frame
		if int(seen["pause_on"]) >= 0 and la.paused == 0 and int(seen["resume_on"]) < 0:
			seen["resume_on"] = la.frame
		if la.speed_q == 16 and int(seen["speed_on"]) < 0:
			seen["speed_on"] = la.frame
		if not la.is_active(1) and int(seen["took"]) < 0 and la.u_cmd[2] == 0:
			seen["took"] = la.frame
		if int(seen["took"]) >= 0 and la.is_active(1) and la.u_cmd[2] == 1 and int(seen["back"]) < 0:
			seen["back"] = la.frame
		if step == 240:
			# A joiner: player 0's snapshot plus everything the relay has passed on.
			joiner = Peer.new()
			joiner.me = 2
			joiner.ls = Lockstep.new()
			joiner.ls.setup(scn, 4243, home, [0, 1], 0)
			if not joiner.ls.restore(a.ls.snapshot()):
				fails += 1
				printerr("FAIL sea co-op: the joiner could not restore player 0's snapshot")
			join_from = joiner.ls.frame
			for item in sent:
				if str(item[0]) == "in":
					joiner.ls.receive(item[1])
				else:
					joiner.ls.receive_event(item[1])
					joiner.ls.saw(1)
		if a.ls.sim.ended != 0 and b.ls.sim.ended != 0 and (joiner == null or joiner.ls.sim.ended != 0):
			break
	var n_cmp := 0
	var bad := -1
	for f in a.hashes:
		if b.hashes.has(f):
			n_cmp += 1
			if int(a.hashes[f]) != int(b.hashes[f]) and bad < 0:
				bad = int(f)
	var n_j := 0
	var bad_j := -1
	for f in joiner.hashes:
		if a.hashes.has(f) and int(f) > join_from:
			n_j += 1
			if int(a.hashes[f]) != int(joiner.hashes[f]) and bad_j < 0:
				bad_j = int(f)
	var st: Dictionary = a.ls.sim.stats
	if bad >= 0 or bad_j >= 0:
		fails += 1
		printerr("FAIL sea co-op: hashes differ (players at frame %d, joiner at %d)" % [bad, bad_j])
	elif n_cmp < 400 or n_j < 200:
		fails += 1
		printerr("FAIL sea co-op: too few frames compared (%d, joiner %d)" % [n_cmp, n_j])
	else:
		print("PASS sea co-op: two players equal on %d frames, a joiner from frame %d on %d (end tick %d, winner %d)" % [
			n_cmp, join_from, n_j, int(a.ls.sim.tick), int(a.ls.sim.winner)])
	var want := {"gift (sloop to player 0)": int(seen["gift_at"]) >= 0, "player 0 ordered the given sloop": int(seen["sloop_ordered"]) >= 0,
		"player 1's order for it refused alike": a.ls.rejected >= 1 and a.ls.rejected == b.ls.rejected,
		"paused by vote": int(seen["pause_on"]) >= 0, "resumed by vote": int(seen["resume_on"]) >= 0,
		"4x by vote": int(seen["speed_on"]) >= 0, "player 1 dropped, ships to player 0": int(seen["took"]) >= 0,
		"admitted again, ships back": int(seen["back"]) >= 0, "a deck melee": int(st["deck_fights"]) > 0,
		"the fire ship lit": int(st["fireships"]) > 0, "the end on all three": a.ls.sim.ended != 0 and joiner.ls.sim.ended != 0}
	for k in want:
		if not bool(want[k]):
			fails += 1
			printerr("FAIL sea co-op: %s %s" % [k, seen])
	if fails == 0:
		print("PASS sea co-op: gift at frame %d (refused foreign orders %d / %d), pause %d-%d, 4x at %d, drop -> player 0 at %d, back at %d; deck fights %d (taken %d), fire ships %d, contacts %d" % [
			int(seen["gift_at"]), a.ls.rejected, b.ls.rejected, int(seen["pause_on"]), int(seen["resume_on"]), int(seen["speed_on"]),
			int(seen["took"]), int(seen["back"]), int(st["deck_fights"]), int(st["deck_taken"]), int(st["fireships"]),
			int(st["fire_contacts"])])
	return fails


# --------------------------------------------------------------- campaign ---

## The campaign round trip (West, England a player): returns failures.
static func campaign(check: Callable) -> void:
	var CData = load("res://campaign/cdata.gd")
	var CState = load("res://campaign/cstate.gd")
	var CTurn = load("res://campaign/cturn.gd")
	var CGrid = load("res://campaign/cgrid.gd")
	var CRules = load("res://campaign/crules.gd")
	var CFleet = load("res://campaign/cfleet.gd")
	var CBattle = load("res://campaign/cbattle.gd")
	var CSeaBattle = load("res://campaign/cseabattle.gd")
	CData.use_pack("west")
	var eng: int = CData.faction_index("england")
	var sp: int = CData.faction_index("new_spain")
	var st: Dictionary = CState.new_campaign("w", 11, [eng], {}, [], "west")
	var open := -1
	for c in CGrid.count():
		if CFleet.is_sea(c) and CFleet.coast_dist(c) >= 3 and CGrid.cy(c) > 20 and CGrid.cx(c) > 60 and CGrid.cx(c) < 120:
			var ok := true
			for dx in range(-8, 9):
				var j: int = CGrid.at(CGrid.cx(c) + dx, CGrid.cy(c))
				if j < 0 or not CFleet.is_sea(j):
					ok = false
			if ok:
				open = c
				break
	var army: Dictionary = (CState.armies_of(st, eng)[0] as Dictionary).duplicate(true)
	st["armies"].erase(CState.army(st, int(army["id"])))
	var e1 := {"id": 900, "f": eng, "x": CGrid.cx(open) + 5, "y": CGrid.cy(open), "ships": [{"t": "frigate", "h": 100, "c": 100},
		{"t": "brigantine", "h": 90, "c": 95}], "carry": [army], "moved": 0}
	var e2 := {"id": 901, "f": sp, "x": CGrid.cx(open) - 5, "y": CGrid.cy(open), "ships": [{"t": "galleon", "h": 100, "c": 100,
		"g": 600, "nm": "San Pedro"}, {"t": "sloop", "h": 100, "c": 100}], "carry": [], "moved": 0}
	st["fleets"] = [e1, e2]
	# A player's voyage into the Spaniard: through the turn, a pending sea battle.
	var sub: Dictionary = CTurn.submission(st, eng, [{"t": "fmove", "fleet": 900, "x": CGrid.cx(open) - 5, "y": CGrid.cy(open),
		"tgt": 901}])
	var s1: Dictionary = CTurn.resolve_turn(st, [sub])
	var pend: Array = CTurn.pending_for(s1, eng)
	var b: Dictionary = pend[0] if not pend.is_empty() else {}
	check.call(not b.is_empty() and int(b.get("sea", 0)) == 1 and str(s1["phase"]) == "battles"
		and CRules.battle_humans(s1, b) == [eng] and CFleet.fleet(s1, 900).has("busy") and CFleet.fleet(s1, 901).has("busy"),
		"sea: a player's voyage into an enemy fleet leaves a pending sea battle (phase %s)" % str(s1["phase"]))
	if b.is_empty():
		CData.use_pack("rome")
		return
	check.call(CState.battle_at(s1, int(b["r"])).is_empty() and (b["af"] as Array) == [900] and (b["df"] as Array) == [901],
		"sea: the battle is off %s, not in it; fleets 900 against 901" % str(CData.REGIONS[int(b["r"])]["city"]))
	var js: Dictionary = CState.from_json(CState.to_json(s1))
	check.call(CState.hash_text(js) == CState.hash_text(s1), "sea: the pending state round-trips JSON")
	var built: Dictionary = CBattle.build(s1, b, eng)
	var scn: Dictionary = built["scenario"]
	check.call(int(scn.get("sea", 0)) == 1 and (scn["units"] as Array).size() == 4 and scn["ai_sides"] == [0, 1]
		and int(scn["units"][0]["troops"]) > 0, "sea: the scenario: 4 ships, the player commands side 0, troops aboard (%d men)" % int(scn["units"][0].get("troops", 0)))
	var built2: Dictionary = CBattle.build(s1, b, eng)
	check.call(str(built2) == str(built), "sea: the same scenario twice")
	# Fight it (the AI sails both sides here), then write it back.
	scn["ai_sides"] = [1, 1]
	var sim := SeaSim.new()
	sim.setup(scn, int(built["seed"]))
	while sim.ended == 0 and sim.tick < 9200:
		sim.step()
	var outcome: Dictionary = CSeaBattle.outcome_from_result(built, sim.result(), "fought")
	var a1: Dictionary = CTurn.apply_battle(s1, int(b["id"]), outcome)
	var a2: Dictionary = CTurn.apply_battle(s1, int(b["id"]), outcome)
	var ev := {}
	for e in a1["events"]:
		if str(e["k"]) == "sea_battle":
			ev = e
	var lost: Array = ev.get("lost", [])
	var fates := ""
	for r in outcome["ships"]:
		fates += "%d/%d:%s h%d c%d " % [int(r[0]), int(r[1]), ["afloat", "sunk", "taken", "escaped"][int(r[2])], int(r[3]), int(r[4])]
	check.call(not ev.is_empty() and int(ev.get("fought", 0)) == 1 and str(a1["phase"]) == "plan" and (a1["battles"] as Array).is_empty(),
		"sea: fought (%d s, %s won) and applied: %s; lost %s, taken %d" % [int(outcome["ticks"]) / 10,
		"att" if int(outcome["winner"]) == 0 else "def", fates, str(lost), int(ev.get("taken", 0))])
	check.call(CState.hash_text(a1) == CState.hash_text(a2), "sea: applying the outcome is the same twice (%s)" % CState.hash_text(a1))
	var lost_n := [0, 0]
	for r in outcome["ships"]:
		if int(r[2]) == 1 or int(r[2]) == 2:
			lost_n[0 if int(r[0]) == 900 else 1] += 1
	var f900: Dictionary = CFleet.fleet(a1, 900)
	var f901: Dictionary = CFleet.fleet(a1, 901)
	var n900: int = (f900["ships"] as Array).size() if not f900.is_empty() else 0
	var n901: int = (f901["ships"] as Array).size() if not f901.is_empty() else 0
	check.call(not f900.has("busy") and not f901.has("busy") and n900 + n901 == 4 - lost_n[0] - lost_n[1] + int(ev.get("taken", 0)),
		"sea: ships after the battle %d + %d (lost %d + %d, prizes %d)" % [n900, n901, lost_n[0], lost_n[1], int(ev.get("taken", 0))])
	var js2: Dictionary = CState.from_json(CState.to_json(a1))
	check.call(CState.hash_text(js2) == CState.hash_text(a1), "sea: the state after the battle round-trips JSON")
	# Auto-resolve: the formula at apply time.
	var a3: Dictionary = CTurn.apply_battle(s1, int(b["id"]), CBattle.formula(s1, b))
	var ev3 := {}
	for e in a3["events"]:
		if str(e["k"]) == "sea_battle":
			ev3 = e
	check.call(not ev3.is_empty() and int(ev3.get("auto", 0)) == 1 and (a3["battles"] as Array).is_empty(),
		"sea: auto-resolve applies the formula (won by %s)" % ("att" if int(ev3.get("won", 1)) == 0 else "def"))
	# AI against AI: still resolved at once.
	var s4: Dictionary = st.duplicate(true)
	s4["humans"] = []
	var s5: Dictionary = CTurn.resolve_turn(s4, [])
	var auto := false
	for e in s5["events"]:
		if str(e["k"]) == "sea_battle" and int(e.get("auto", 0)) == 1:
			auto = true
	var sea_pending := false
	for bb in s5["battles"]:
		if bb.has("sea"):
			sea_pending = true
	check.call(not sea_pending, "sea: without a player no sea battle is pending (one auto-resolved this turn: %s)" % auto)
	CData.use_pack("rome")
