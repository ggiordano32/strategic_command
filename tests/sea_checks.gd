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
## them broadsides, raking, chain and grape, a boarding and a capture, a
## ship striking, tacking or wearing all happened. A table of each battle
## (time to decide, winner, ships sunk / taken / escaped) is printed.
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

const SCENARIOS: Array[String] = ["frigates", "sloops_galleon", "boarding", "upwind", "downwind", "coast"]


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
	for k in ["broadsides", "rakes", "chain", "grape", "boardings", "captured", "struck"]:
		if int(cover.get(k, 0)) <= 0:
			fails += 1
			printerr("FAIL sea coverage: no %s in any battle" % k)
	if int(cover.get("tacks", 0)) + int(cover.get("wears", 0)) <= 0:
		fails += 1
		printerr("FAIL sea coverage: nobody tacked or wore")
	print("sea coverage: ", cover)
	for line in table:
		print(line)
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
