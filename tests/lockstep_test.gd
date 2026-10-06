extends SceneTree
## Headless lockstep test (milestone 5), no network:
##   godot --headless --script res://tests/lockstep_test.gd [-- --quick]
##
## 1. Sim snapshot / restore: on several scenarios (terrain, artillery,
##    cavalry, projectiles in flight, pending orders) a sim restored from a
##    snapshot has the source's hash and stays identical tick by tick.
##    Snapshot sizes at 2,000 and 4,000 soldiers are printed.
## 2. Lockstep: two peers (players 0 and 1, the enemy under the battle AI)
##    exchange messages through a simulated relay (server sequence numbers,
##    a different random latency per peer, FIFO per peer) and issue
##    scripted random orders with different local timing: orders for their
##    own units and for the other's (refused alike), gifts and gifts back,
##    pause and speed votes with acceptances and refusals, an army
##    withdrawal of one player. The lockstep hash must be equal on every
##    frame. Then a disconnect: the relay drops player 1 (takeover: player
##    0 commands every friendly unit), player 1 comes back by snapshot,
##    catches up, says ready, is admitted and regains command.
## 3. A third peer joins mid-battle from a snapshot plus the relay's buffer
##    and reproduces the host's hash on every later frame.
## 4. A solo run of the same scenario through Lockstep with one player
##    equals a plain BattleSim run with the same orders (the lockstep layer
##    adds nothing to solo play).
## 5. Settlement battles (city maps: paths, gates, the plaza): two peers
##    attacking a walled town (orders at its gates for batteries and foot)
##    and two peers defending one (opening and closing gates), every frame
##    equal; snapshots of woods and city battles restore exactly (in 1).
## Exits 0 on success.

const BattleSim := preload("res://sim/battle_sim.gd")
const Lockstep := preload("res://sim/lockstep.gd")
const Scenarios := preload("res://sim/scenarios.gd")
const UT := preload("res://sim/unit_types.gd")

var _ok := true
var quick := false


func _init() -> void:
	quick = OS.get_cmdline_user_args().has("--quick")
	_test_snapshots()
	_test_lockstep()
	_test_solo_equivalence()
	_test_lockstep_city(1)
	_test_lockstep_city(0)
	_test_lockstep_city(1, true)
	_test_lockstep_city(0, true)
	print("RESULT: %s" % ("PASS" if _ok else "FAIL"))
	quit(0 if _ok else 1)


func _fail(msg: String) -> void:
	_ok = false
	printerr("FAIL " + msg)


# ------------------------------------------------------------ snapshots ---

func _test_snapshots() -> void:
	var cases := [["skirmish", 400], ["battle_2000", 700], ["test_cav_art", 250], ["test_stone_line", 300],
		["bench_4000", 600], ["bench_4000_hills", 50], ["test_woods", 500], ["siege_city", 900],
		["bench_4000_city", 1200], ["siege_polis", 900], ["siege_castrum", 700], ["siege_oppidum", 600]]
	for c in cases:
		var scen: Dictionary = Scenarios.make(str(c[0]))
		var a := BattleSim.new()
		a.setup(scen, 777)
		var at: int = c[1]
		for t in at:
			a.step()
		# A pending order the restored sim must apply too.
		for u in a.n_units:
			if a.u_side[u] == 0 and a.u_state[u] == BattleSim.U_READY:
				a.queue_order(BattleSim.make_halt_order(a.tick + 2, u))
				break
		var t0 := Time.get_ticks_usec()
		var blob := a.snapshot()
		var ms_snap := (Time.get_ticks_usec() - t0) / 1000.0
		var b := BattleSim.new()
		b.setup(scen, 777)
		t0 = Time.get_ticks_usec()
		var ok := b.restore(blob)
		var ms_rest := (Time.get_ticks_usec() - t0) / 1000.0
		if not ok:
			_fail("%s: restore refused its own snapshot" % c[0])
			continue
		if a.state_hash() != b.state_hash():
			_fail("%s: hash after restore %08x != %08x" % [c[0], b.state_hash(), a.state_hash()])
			continue
		var bad := -1
		var step_us := 0
		var nsteps := 150 if quick else 400
		for t in nsteps:
			a.step()
			var ts := Time.get_ticks_usec()
			b.step()
			step_us += Time.get_ticks_usec() - ts
			if a.state_hash() != b.state_hash():
				bad = a.tick
				break
		if bad >= 0:
			_fail("%s: restored sim diverged at tick %d" % [c[0], bad])
		else:
			print("PASS snapshot %s at tick %d: %d soldiers, %d projectiles, %d bytes (%.1f ms snapshot, %.1f ms restore), identical after; catch-up stepping %.2f ms/tick here" % [
				c[0], at, a.n, a.pr_count, blob.size(), ms_snap, ms_rest, step_us / 1000.0 / nsteps])
		# A snapshot of another battle is refused.
		var other := BattleSim.new()
		other.setup(Scenarios.make("test_pike_front"), 777)
		if other.restore(blob):
			_fail("%s: a snapshot was accepted by a different battle" % c[0])


# ------------------------------------------------------------- lockstep ---

## The relay: stamps sequence numbers, keeps everything, delivers to each
## peer in order after that peer's latency (in steps of the test clock).
class Relay:
	var items: Array = []      # {s, at, kind: "in" | "ev", msg}
	var seq := 0
	var last_n := {}           # player -> last message number passed on
	var last_k := {}           # player -> last mark passed on
	var dropped := {}          # player -> true while their input is refused

	func send(now: int, msg: Dictionary) -> bool:
		var p := int(msg["p"])
		if dropped.get(p, false):
			return false
		seq += 1
		last_n[p] = int(msg["n"])
		last_k[p] = maxi(int(last_k.get(p, -1)), int(msg["k"]))
		var m := msg.duplicate(true)
		m["s"] = seq
		items.append({"s": seq, "at": now, "kind": "in", "msg": m})
		return true

	func drop(now: int, who: int, to: int) -> void:
		dropped[who] = true
		seq += 1
		items.append({"s": seq, "at": now, "kind": "ev", "msg": {"s": seq, "t": "drop", "who": who,
			"after": int(last_k.get(who, -1)), "to": to}})


class Peer:
	var ls
	var me := 0
	var name := ""
	var d := 3
	var sent_k := -1
	var n := 0
	var outbox: Array = []
	var cursor := 0            # next relay item index to deliver
	var latency := 2
	var rng := RandomNumberGenerator.new()
	var hashes := {}           # frame -> hash
	var online := true
	var admitted_at := -1      # frame of our admission seen in the stream

	func issue(o: Dictionary) -> void:
		outbox.append(o)

	## Send what is queued and advance our mark.
	func flush(relay, now: int) -> void:
		if not online:
			return
		var target: int = ls.frame + d
		if admitted_at >= 0:
			target = maxi(target, admitted_at)
		if not ls.is_active(me) and admitted_at < 0:
			outbox.clear()
			return
		var k := maxi(target, sent_k)
		if not outbox.is_empty():
			k = maxi(k, sent_k + 1)
		if k <= sent_k:
			return
		var os: Array = []
		for o in outbox:
			var o2: Dictionary = o.duplicate()
			o2["f"] = k
			os.append(o2)
		outbox.clear()
		n += 1
		sent_k = k
		var msg := {"p": me, "n": n, "k": k, "o": os}
		ls.receive(msg)
		relay.send(now, msg)

	func deliver(relay, now: int) -> void:
		if not online:
			return
		while cursor < relay.items.size():
			var it: Dictionary = relay.items[cursor]
			if int(it["at"]) + latency > now:
				break
			cursor += 1
			_take(it)

	func _take(it: Dictionary) -> void:
		var m: Dictionary = it["msg"]
		if str(it["kind"]) == "in":
			var r: String = ls.receive(m)
			if r == "gap":
				push_error("%s: gap in the stream at s=%d" % [name, int(it["s"])])
			for o in m.get("o", []):
				if int(o.get("type", 0)) == Lockstep.C_ADMIT and int(o.get("who", -1)) == me:
					admitted_at = int(o["f"])
		else:
			ls.receive_event(m)
		ls.saw(int(it["s"]))

	## Up to `budget` frames if the inputs are there.
	func run(budget: int, hash_all: bool) -> int:
		var done := 0
		while done < budget and ls.can_advance():
			ls.advance()
			done += 1
			if hash_all:
				hashes[ls.frame] = ls.state_hash()
		return done


func _home_split(sim) -> Array:
	# Side 0 units alternate between players 0 and 1; the enemy is AI.
	var home: Array = []
	var k := 0
	for u in sim.n_units:
		if sim.u_side[u] == 0:
			home.append(k % 2)
			k += 1
		else:
			home.append(-1)
	return home


func _new_peer(scen: Dictionary, home: Array, me: int, nm: String, present: Array) -> Peer:
	var p := Peer.new()
	p.ls = Lockstep.new()
	p.ls.setup(scen, 4242, home, present, 0)
	p.me = me
	p.name = nm
	p.rng.seed = 1000 + me * 77
	return p


## Random orders for this peer: mostly for its own units, some for the
## other's (must be refused alike), gifts, votes.
func _script(p: Peer, step: int, enemy: Array) -> void:
	var sim = p.ls.sim
	var r := p.rng.randi() % 100
	if r < 6:
		var u: int = p.rng.randi() % sim.n_units
		if sim.u_side[u] != 0:
			return
		var x: int = sim.u_ax[u] + (p.rng.randi() % 41 - 20) * 1024
		var y: int = sim.u_ay[u] - (p.rng.randi() % 30) * 1024
		p.issue({"type": BattleSim.ORDER_MOVE, "unit": u, "x": x, "y": y, "facing": 768,
			"width": 30 * 1024, "run": p.rng.randi() % 2})
	elif r < 9 and not enemy.is_empty():
		var u2: int = p.rng.randi() % sim.n_units
		if sim.u_side[u2] == 0:
			p.issue({"type": BattleSim.ORDER_ATTACK, "unit": u2, "target": enemy[p.rng.randi() % enemy.size()], "run": 1})
	elif r == 10:
		# Gift one of my units to the other player.
		for u in sim.n_units:
			if p.ls.u_cmd[u] == p.me and p.rng.randi() % 3 == 0:
				p.issue({"type": Lockstep.C_GIFT, "unit": u, "to": 1 - p.me})
				break
	elif r == 11 and step % 7 == 0:
		p.issue({"type": Lockstep.C_PAUSE, "want": 1 - p.ls.paused})
	elif r == 12:
		p.issue({"type": Lockstep.C_SPEED, "q": [2, 4, 8, 4][p.rng.randi() % 4]})
	elif r == 13:
		# Answer whatever vote the other has pending (sometimes no).
		if p.ls.vote_pause_by >= 0 and p.ls.vote_pause_by != p.me:
			p.issue({"type": Lockstep.C_ANSWER, "what": 0, "yes": 1 if p.rng.randi() % 4 != 0 else 0})
		if p.ls.vote_speed_by >= 0 and p.ls.vote_speed_by != p.me:
			p.issue({"type": Lockstep.C_ANSWER, "what": 1, "yes": 1})


func _compare(a: Peer, b: Peer, from_frame: int, what: String) -> int:
	var n_cmp := 0
	for f in a.hashes:
		if int(f) < from_frame or not b.hashes.has(f):
			continue
		n_cmp += 1
		if int(a.hashes[f]) != int(b.hashes[f]):
			_fail("%s: %s and %s differ at frame %d (%08x vs %08x)" % [what, a.name, b.name, int(f), int(a.hashes[f]), int(b.hashes[f])])
			return -1
	return n_cmp


func _test_lockstep() -> void:
	var scen: Dictionary = Scenarios.make("battle_2000")
	scen["ai_sides"] = [1]
	var probe := BattleSim.new()
	probe.setup(scen, 4242)
	var home := _home_split(probe)
	var enemy: Array = []
	for u in probe.n_units:
		if probe.u_side[u] == 1:
			enemy.append(u)
	var relay := Relay.new()
	var a := _new_peer(scen, home, 0, "A", [0, 1])
	var b := _new_peer(scen, home, 1, "B", [0, 1])
	a.latency = 1
	b.latency = 3
	b.d = 4
	var peers: Array[Peer] = [a, b]
	var waits := {"A": 0, "B": 0}
	var stats := {"pauses": 0, "speeds": 0, "gifts_ok": 0}
	var total := 900 if quick else 2200
	var now := 0
	var drop_at := total / 2
	var back_at := drop_at + 60
	var withdraw_at := total - 300
	var c: Peer = null
	var c_join := total / 3
	var max_frames := 0
	while now < total * 3 and max_frames < total:
		now += 1
		for p in peers:
			# Different local timing: each peer runs 0-2 frames per clock step.
			if not p.online:
				continue
			_script(p, now, enemy)
			if p.me == 1 and now == withdraw_at and p.ls.is_active(1):
				p.issue({"type": BattleSim.ORDER_WITHDRAW_ALL, "side": 0})
			p.flush(relay, now)
			p.deliver(relay, now)
			var budget := p.rng.randi() % 3
			var before: int = p.ls.frame
			p.run(budget, true)
			if p.ls.frame == before and budget > 0:
				waits[p.name] = int(waits[p.name]) + 1
		if c != null:
			c.flush(relay, now)
			c.deliver(relay, now)
			c.run(4, true)  # catches up faster
		max_frames = mini(a.ls.frame, b.ls.frame) if b.online else a.ls.frame
		# Third peer (an observer of player 1's seat) joins mid-battle by
		# snapshot + the relay's buffer.
		if now == c_join:
			c = _new_peer(scen, home, 1, "C", [0, 1])
			c.online = true
			c.latency = 2
			var blob: PackedByteArray = a.ls.snapshot()
			if not c.ls.restore(blob):
				_fail("C could not restore A's snapshot")
				return
			if c.ls.state_hash() != a.ls.state_hash():
				_fail("C's hash after restore differs from A's")
			c.hashes[c.ls.frame] = c.ls.state_hash()
			# Replay the relay from the snapshot's last sequence number.
			c.cursor = 0
			while c.cursor < relay.items.size() and int(relay.items[c.cursor]["s"]) <= c.ls.last_s:
				c.cursor += 1
			c.sent_k = 1 << 30  # C never sends (it is not a player)
			print("  C joined at frame %d from a %d-byte snapshot (relay at s=%d, snapshot s=%d)" % [
				c.ls.frame, blob.size(), relay.seq, c.ls.last_s])
		# Disconnect of B: the relay drops it, A takes over.
		if now == drop_at:
			b.online = false
			relay.drop(now, 1, 0)
		if now == back_at:
			# B comes back: snapshot from A, replay, then ready -> A admits.
			var nb := _new_peer(scen, home, 1, "B", [0, 1])
			nb.latency = b.latency
			nb.d = b.d
			if not nb.ls.restore(a.ls.snapshot()):
				_fail("B could not restore after reconnecting")
				return
			nb.cursor = 0
			while nb.cursor < relay.items.size() and int(relay.items[nb.cursor]["s"]) <= nb.ls.last_s:
				nb.cursor += 1
			nb.n = int(relay.last_n.get(1, 0))
			nb.sent_k = int(relay.last_k.get(1, -1))
			nb.hashes = b.hashes
			nb.hashes[nb.ls.frame] = nb.ls.state_hash()
			relay.dropped.erase(1)
			b = nb
			peers[1] = b
			# A admits B (as the host does when B says ready).
			a.issue({"type": Lockstep.C_ADMIT, "who": 1, "keep": 0})
	# Checks.
	var n_ab := _compare(a, b, 0, "A/B")
	var n_ac := _compare(a, c, c_join, "A/C") if c != null else 0
	var mine := 0
	for u in a.ls.u_cmd.size():
		if a.ls.u_cmd[u] == 1:
			mine += 1
	print("PASS lockstep: A at frame %d, B at %d; %d frames compared A/B, %d A/C; waits A %d B %d; sim tick %d; rejected %d, late %d; B commands %d units at the end; paused %d speed %d" % [
		a.ls.frame, b.ls.frame, n_ab, n_ac, waits["A"], waits["B"], a.ls.sim.tick, a.ls.rejected, a.ls.late, mine,
		a.ls.paused, a.ls.speed_q] if n_ab > 0 else "lockstep: nothing compared")
	if n_ab < total / 2:
		_fail("too few frames compared (%d)" % n_ab)
	if c != null and n_ac < 100:
		_fail("too few frames compared for the mid-battle joiner (%d)" % n_ac)
	if a.ls.rejected == 0:
		_fail("no order was refused (orders for the other player's units should be)")
	if not a.ls.is_active(1) or mine == 0:
		_fail("B did not regain command after being admitted again")
	if a.ls.sim.tick < 300:
		_fail("the sim hardly ran (tick %d)" % a.ls.sim.tick)
	stats["pauses"] = 0
	# Deterministic unit-level checks of the control inputs.
	_check_controls(scen, home)


## Small direct checks of the vote, gift, drop and admit rules.
func _check_controls(scen: Dictionary, home: Array) -> void:
	var ls := Lockstep.new()
	ls.setup(scen, 9, home, [0, 1], 0)
	var cnt := {0: 0, 1: 0}
	var send := func(p: int, k: int, os: Array) -> void:
		cnt[p] = int(cnt[p]) + 1
		for o in os:
			o["f"] = k
		ls.receive({"p": p, "n": cnt[p], "k": k, "o": os})
	# Frame 0: player 0 asks for pause; not yet paused.
	send.call(0, 0, [{"type": Lockstep.C_PAUSE, "want": 1}])
	send.call(1, 0, [])
	ls.advance()
	if ls.paused != 0 or ls.vote_pause_by != 0:
		_fail("a pause request applied without the other's agreement")
	# Frame 1: player 1 taps pause too: accepted.
	send.call(1, 1, [{"type": Lockstep.C_PAUSE, "want": 1}])
	send.call(0, 1, [])
	var t0: int = ls.sim.tick
	ls.advance()
	if ls.paused != 1 or ls.vote_pause_by != -1:
		_fail("pause not applied after both asked")
	if ls.can_advance():
		ls.advance()
	# Speed request refused.
	send.call(0, 3, [{"type": Lockstep.C_SPEED, "q": 8}])
	send.call(1, 3, [])
	while ls.frame <= 3:
		ls.advance()
	send.call(1, 4, [{"type": Lockstep.C_ANSWER, "what": 1, "yes": 0}])
	send.call(0, 4, [])
	ls.advance()
	if ls.speed_q != 4 or ls.vote_speed_by != -1:
		_fail("a refused speed request was applied or stayed pending")
	if ls.sim.tick != t0:
		_fail("the sim stepped while paused (tick %d, paused at %d)" % [ls.sim.tick, t0])
	# Gift: player 1 gifts unit u (theirs) to 0; player 0 then orders it,
	# player 1's order for it is refused.
	var u := -1
	for i in ls.u_cmd.size():
		if ls.u_cmd[i] == 1:
			u = i
			break
	send.call(1, 5, [{"type": Lockstep.C_GIFT, "unit": u, "to": 0}])
	send.call(0, 5, [{"type": Lockstep.C_GIFT, "unit": u, "to": 1}])  # not theirs yet: refused
	ls.advance()
	if ls.u_cmd[u] != 0:
		_fail("gift not applied (cmd %d)" % ls.u_cmd[u])
	var rej: int = ls.rejected
	send.call(1, 6, [{"type": BattleSim.ORDER_HALT, "unit": u}])
	send.call(0, 6, [{"type": BattleSim.ORDER_HALT, "unit": u}])
	ls.advance()
	if ls.rejected != rej + 1:
		_fail("an order for a gifted-away unit was not refused")
	# Gift back.
	send.call(0, 7, [{"type": Lockstep.C_GIFT, "unit": u, "to": 1}])
	send.call(1, 7, [])
	ls.advance()
	if ls.u_cmd[u] != 1:
		_fail("gift back not applied")
	# Drop player 1 after frame 8: player 0 takes over; pauses then apply
	# immediately (one player left).
	send.call(1, 8, [])
	send.call(0, 8, [])
	ls.receive_event({"s": 1, "t": "drop", "who": 1, "after": 8, "to": 0})
	ls.advance()
	send.call(0, 12, [{"type": Lockstep.C_PAUSE, "want": 0}])
	while ls.frame <= 12 and ls.can_advance():
		ls.advance()
	var held := 0
	for i in ls.u_cmd.size():
		if ls.u_away[i] == 1:
			held += 1
			if ls.u_cmd[i] != 0:
				_fail("a dropped player's unit did not go to the remaining player")
	if ls.is_active(1) or held == 0:
		_fail("drop not applied")
	if ls.paused != 0:
		_fail("with one player left a resume did not apply at once")
	# Admit player 1 again: units come back.
	send.call(0, 14, [{"type": Lockstep.C_ADMIT, "who": 1, "keep": 0}])
	while ls.frame <= 14 and ls.can_advance():
		ls.advance()
	if not ls.is_active(1):
		_fail("admit did not apply")
	for i in ls.u_cmd.size():
		if ls.u_home[i] == 1 and ls.u_cmd[i] != 1 and i != u:
			_fail("unit %d not returned to player 1 on admission" % i)
			break
	if ls.can_advance():
		_fail("after admission the sim did not wait for the admitted player's input")
	# Snapshot round trip of the lockstep layer.
	var blob: PackedByteArray = ls.snapshot()
	var ls2 := Lockstep.new()
	ls2.setup(scen, 9, home, [0, 1], 0)
	if not ls2.restore(blob) or ls2.state_hash() != ls.state_hash():
		_fail("lockstep snapshot round trip changed the hash")
	else:
		print("PASS controls: votes, refusal, gift and gift back, order refusal, drop + takeover, admit + return, snapshot round trip")


## One player alone through Lockstep (delay 0) = the plain sim with the
## same orders applied on the same ticks.
func _test_solo_equivalence() -> void:
	var scen: Dictionary = Scenarios.make("skirmish")
	scen["ai_sides"] = [1]
	var plain := BattleSim.new()
	plain.setup(scen, 31)
	var home: Array = []
	for u in plain.n_units:
		home.append(0 if plain.u_side[u] == 0 else -1)
	var ls := Lockstep.new()
	ls.setup(scen, 31, home, [0], 0)
	var n := 0
	var bad := -1
	for t in 800:
		var os: Array = []
		if t % 97 == 5:
			for u in plain.n_units:
				if plain.u_side[u] == 0:
					var o := BattleSim.make_move_order(plain.tick, u, plain.u_ax[u], plain.u_ay[u] - 20 * 1024, 768, 25 * 1024, 1)
					o["player"] = 0
					o["seq"] = (n + 1) * 64 + os.size()
					plain.queue_order(o)
					var lo := o.duplicate()
					lo.erase("tick")
					lo.erase("player")
					lo.erase("seq")
					lo["f"] = ls.frame
					os.append(lo)
		n += 1
		ls.receive({"p": 0, "n": n, "k": ls.frame, "o": os})
		ls.advance()
		plain.step()
		if ls.sim.state_hash() != plain.state_hash():
			bad = t
			break
	if bad >= 0:
		_fail("solo through lockstep differs from the plain sim at tick %d" % bad)
	else:
		print("PASS solo through lockstep equals the plain sim (800 ticks)")



# ---------------------------------------------------------- settlements ---

## Two peers on a walled town: attacking it (def_side 1; random orders plus
## orders at the gates for their batteries and foot), or defending it
## (def_side 0; random orders plus opening and closing gates; the AI
## attacks). Every frame's lockstep hash must agree.
func _test_lockstep_city(def_side: int, polis := false) -> void:
	var scen: Dictionary = Scenarios.siege_test(202, 1, 1, 2, 1, def_side)
	if polis:
		# A coastal polis on a hill with its acropolis: the gate orders
		# include the citadel's; defending players send wall units down
		# the stairs and back up onto other stretches.
		scen = Scenarios.siege_test(606, 2, 2, 2, 4, def_side, -1, 1, 1)
	scen["ai_sides"] = [1]
	var probe := BattleSim.new()
	probe.setup(scen, 4242)
	var home := _home_split(probe)
	var enemy: Array = []
	for u in probe.n_units:
		if probe.u_side[u] == 1:
			enemy.append(u)
	var relay := Relay.new()
	var a := _new_peer(scen, home, 0, "A", [0, 1])
	var b := _new_peer(scen, home, 1, "B", [0, 1])
	a.latency = 1
	b.latency = 3
	b.d = 4
	var peers: Array[Peer] = [a, b]
	var total := 400 if quick else 1200
	var now := 0
	var gate_orders := 0
	var wall_orders := 0
	while now < total * 3 and mini(a.ls.frame, b.ls.frame) < total:
		now += 1
		for p in peers:
			_script(p, now, enemy)
			var sim = p.ls.sim
			if def_side == 0 and polis and now % 53 == p.me * 17 and sim.ws_x0.size() > 1:
				# A wall unit down to the agora, or a unit on the ground up
				# onto a stretch of wall.
				for u in sim.n_units:
					if p.ls.u_cmd[u] != p.me or sim.u_state[u] != BattleSim.U_READY or sim.u_stair[u] != 0:
						continue
					if sim.u_wall[u] > 0:
						p.issue({"type": BattleSim.ORDER_MOVE, "unit": u, "x": sim.agora[0], "y": sim.agora[1],
							"facing": 256, "width": 12 * 1024, "run": 1})
					elif UT.cls(sim.u_type[u]) == UT.CLS_MISSILE:
						var sg: int = (now / 53) % sim.ws_x0.size()
						p.issue({"type": BattleSim.ORDER_MOVE, "unit": u, "x": (sim.ws_x0[sg] + sim.ws_x1[sg]) / 2,
							"y": (sim.ws_y0[sg] + sim.ws_y1[sg]) / 2, "facing": 256, "width": 12 * 1024, "run": 0})
					else:
						continue
					wall_orders += 1
					break
			if now % 37 == p.me * 11 and sim.n_gates > 0:
				# Orders at the gates by one of this player's units.
				for u in sim.n_units:
					if p.ls.u_cmd[u] != p.me or sim.u_state[u] != BattleSim.U_READY:
						continue
					var g: int = (now / 37) % sim.n_gates
					if def_side == 0:
						p.issue({"type": BattleSim.ORDER_GATE, "unit": u, "gate": g, "on": (now / 74) % 2})
					else:
						p.issue({"type": BattleSim.ORDER_ATTACK, "unit": u, "target": -1, "gate": g, "run": 1})
					gate_orders += 1
					break
			p.flush(relay, now)
			p.deliver(relay, now)
			p.run(p.rng.randi() % 3, true)
	var n_ab := _compare(a, b, 0, "city A/B")
	var sim_a = a.ls.sim
	var gs := []
	for g in sim_a.n_gates:
		gs.append(sim_a.g_state[g])
	if n_ab < total / 2:
		_fail("city (defenders on side %d): too few frames compared (%d)" % [def_side, n_ab])
	else:
		print("PASS lockstep on a %s, players %s: %d frames equal A/B; %d gate orders, %d wall orders; gates %s; paths %d, gate opened %d / closed %d / broken %d, stairs down %d / up %d; sim tick %d" % [
			"coastal polis" if polis else "walled town", "attacking" if def_side == 1 else "defending", n_ab,
			gate_orders, wall_orders, str(gs), sim_a.stat_paths, sim_a.stat_gate_open, sim_a.stat_gate_close,
			sim_a.stat_gate_broken, sim_a.stat_stair_down, sim_a.stat_stair_up, sim_a.tick])
		if polis and def_side == 0 and (sim_a.stat_stair_down == 0 or sim_a.stat_stair_up == 0):
			_fail("coastal polis (defending): no wall unit went down and up a stair")
