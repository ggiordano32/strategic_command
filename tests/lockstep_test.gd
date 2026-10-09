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
## 6. AI profiles (sim/ai_profile.gd): a scenario naming the default
##    profile ("ai_skill" / "ai_style" AVERAGE / BALANCED) hashes exactly as
##    one without the keys; another profile is in the hash from tick 0 and
##    survives snapshot / restore (a sim set up with the default profile
##    takes the snapshot's).
## 7. Easy (docs/AI.md step 2: the deliberate-mistake roller draws from the
##    sim's RNG and keeps its cooldowns in hashed sim state): an AI battle
##    with both sides at Easy restored from snapshots at several ticks runs
##    on with the original's hash; two peers against an Easy enemy AI, with
##    a third joining mid-battle by snapshot, hash equal on every frame,
##    and the enemy did make mistakes.
## 8. Skilled (docs/AI.md step 3: its memory, BattleSim.ai_mem, is hashed
##    sim state): AI battles with a Skilled side (both sides on a field, a
##    Skilled attacker and a Skilled defender of a walled city) restored
##    from snapshots at several ticks run on with the original's hash; two
##    peers against a Skilled enemy AI, with a third joining mid-battle by
##    snapshot, hash equal on every frame, and the enemy did use its
##    Skilled behaviours.
## 9. Deployment phase and head-to-head (custom battles): two peers placing
##    their units and readying (one early), a third joining by snapshot
##    during the deployment; head-to-head with the countdown starting the
##    battle, placements of the enemy's units and gifts to the enemy
##    refused, a drop (the AI takes the dropped player's side) and the
##    return (handed back); a drop during the deployment starts the battle
##    without waiting. Every frame equal.
## 11. Units do not pass through each other: two peers fighting a street
##    fight (two columns meeting in a 10 m street, the enemy AI), a third
##    joining by snapshot while units wait behind the fighting ones: every
##    frame equal.
## 10. Siege equipment and wall towers: the equal-force walls-3 siege with
##    ladders, a ram, tower engines and a 20 minute limit, restored from a
##    snapshot taken mid-climb (and at other ticks) runs on identically;
##    two peers attacking it (each sends a ladder unit up a stretch and the
##    ram at the main gate) with a third joining by snapshot while a unit is
##    on its ladders: every frame equal.
## Exits 0 on success.

const BattleSim := preload("res://sim/battle_sim.gd")
const Lockstep := preload("res://sim/lockstep.gd")
const Scenarios := preload("res://sim/scenarios.gd")
const UT := preload("res://sim/unit_types.gd")
const AIProfile := preload("res://sim/ai_profile.gd")

var _ok := true
var quick := false


func _init() -> void:
	quick = OS.get_cmdline_user_args().has("--quick")
	if OS.get_cmdline_user_args().has("--only=deploy"):
		_test_deploy("coop")
		_test_deploy("h2h")
		_test_deploy("h2h_drop")
		print("RESULT: %s" % ("PASS" if _ok else "FAIL"))
		quit(0 if _ok else 1)
		return
	if OS.get_cmdline_user_args().has("--only=siege"):
		_test_siege_snapshots()
		_test_lockstep_siege()
		print("RESULT: %s" % ("PASS" if _ok else "FAIL"))
		quit(0 if _ok else 1)
		return
	if OS.get_cmdline_user_args().has("--only=street"):
		_test_lockstep_street()
		print("RESULT: %s" % ("PASS" if _ok else "FAIL"))
		quit(0 if _ok else 1)
		return
	_test_snapshots()
	_test_profiles()
	_test_lockstep()
	_test_solo_equivalence()
	_test_lockstep_city(1)
	_test_lockstep_city(0)
	_test_lockstep_city(1, true)
	_test_lockstep_city(0, true)
	_test_siege_snapshots()
	_test_lockstep_siege()
	_test_lockstep_street()
	_test_easy_snapshots()
	_test_lockstep_easy()
	_test_skilled_snapshots()
	_test_lockstep_skilled()
	_test_deploy("coop")
	_test_deploy("h2h")
	_test_deploy("h2h_drop")
	print("RESULT: %s" % ("PASS" if _ok else "FAIL"))
	quit(0 if _ok else 1)


func _fail(msg: String) -> void:
	_ok = false
	printerr("FAIL " + msg)


# ------------------------------------------------------------- profiles ---

func _test_profiles() -> void:
	var base := Scenarios.make("skirmish")
	var plain := BattleSim.new()
	plain.setup(base, 7)
	var named := base.duplicate(true)
	named["ai_skill"] = [1, 1]
	named["ai_style"] = [1, 1]
	var dflt := BattleSim.new()
	dflt.setup(named, 7)
	var other := base.duplicate(true)
	other["ai_skill"] = [2, 0]
	other["ai_style"] = [0, 2]
	var prof := BattleSim.new()
	prof.setup(other, 7)
	if dflt.state_hash() != plain.state_hash():
		_fail("profiles: the default profile named in the scenario changed the hash")
	if prof.state_hash() == plain.state_hash():
		_fail("profiles: another profile is not in the hash at tick 0")
	for t in 50:
		prof.step()
	var snap := prof.snapshot()
	var back := BattleSim.new()
	back.setup(base, 7)
	if not back.restore(snap) or back.state_hash() != prof.state_hash() \
			or back.ai_skill != prof.ai_skill or back.ai_style != prof.ai_style:
		_fail("profiles: snapshot / restore lost the AI profile")
	else:
		print("PASS profiles: default hashes as before, others hashed (%08x vs %08x), snapshot keeps them" % [
			prof.state_hash(), plain.state_hash()])


# ----------------------------------------------------------------- easy ---

## Mistakes made by sim side `side` (BattleSim.stat_aic, AIProfile C_MISTAKE..).
static func _mistakes(sim, side: int) -> int:
	var n := 0
	for m in AIProfile.N_MISTAKES:
		n += sim.stat_aic[side * AIProfile.N_COUNTERS + AIProfile.C_MISTAKE + m]
	return n


## Both sides at Easy: snapshot / restore at several ticks runs on exactly.
func _test_easy_snapshots() -> void:
	for key in ["battle_2000", "siege_town"]:
		var scen: Dictionary = Scenarios.make(key)
		scen["ai_sides"] = [0, 1]
		scen["ai_skill"] = [0, 0]
		var a := BattleSim.new()
		a.setup(scen, 31337)
		var bad := 0
		var checks := 0
		for stop in ([600, 1500] if quick else [600, 1500, 2400]):
			while a.tick < stop and a.winner < 0:
				a.step()
			var b := BattleSim.new()
			b.setup(scen, 31337)
			if not b.restore(a.snapshot()) or b.state_hash() != a.state_hash():
				_fail("easy %s: restore at tick %d did not reproduce the hash" % [key, stop])
				return
			for t in 200:
				a.step()
				b.step()
				checks += 1
				if a.state_hash() != b.state_hash():
					bad += 1
		if bad > 0:
			_fail("easy %s: restored copies diverged (%d of %d ticks)" % [key, bad, checks])
		else:
			print("PASS easy %s: both sides Easy, snapshot / restore runs on identically (%d ticks checked), mistakes %d / %d, cooldowns %s" % [
				key, checks, _mistakes(a, 0), _mistakes(a, 1), str(a.ai_mist)])
		if _mistakes(a, 0) + _mistakes(a, 1) == 0:
			_fail("easy %s: no mistake was made" % key)


## Two peers (side 0) against an Easy enemy AI, a third joining mid-battle:
## every frame hash-equal; the enemy made mistakes.
func _test_lockstep_easy() -> void:
	var scen: Dictionary = Scenarios.make("battle_2000")
	scen["ai_sides"] = [1]
	scen["ai_skill"] = [1, 0]
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
	var total := 1200 if quick else 3000
	var c: Peer = null
	var c_join := total / 3
	var now := 0
	while now < total * 3 and mini(a.ls.frame, b.ls.frame) < total:
		now += 1
		for p in peers:
			_script(p, now, enemy)
			p.flush(relay, now)
			p.deliver(relay, now)
			p.run(p.rng.randi() % 3, true)
		if c != null:
			c.flush(relay, now)
			c.deliver(relay, now)
			c.run(4, true)
		if now == c_join:
			c = _new_peer(scen, home, 1, "C", [0, 1])
			c.online = true
			c.latency = 2
			if not c.ls.restore(a.ls.snapshot()):
				_fail("easy lockstep: C could not restore A's snapshot")
				return
			c.hashes[c.ls.frame] = c.ls.state_hash()
			c.cursor = 0
			while c.cursor < relay.items.size() and int(relay.items[c.cursor]["s"]) <= c.ls.last_s:
				c.cursor += 1
			c.sent_k = 1 << 30
	var n_ab := _compare(a, b, 0, "easy A/B")
	var n_ac := _compare(a, c, c_join, "easy A/C") if c != null else 0
	var mk := _mistakes(a.ls.sim, 1)
	if n_ab < total / 2 or n_ac < 100:
		_fail("easy lockstep: too few frames compared (A/B %d, A/C %d)" % [n_ab, n_ac])
	elif n_ab > 0 and n_ac > 0:
		print("PASS easy lockstep: %d frames A/B and %d A/C equal against an Easy enemy (sim tick %d, its mistakes %d)" % [
			n_ab, n_ac, a.ls.sim.tick, mk])
	if mk == 0:
		_fail("easy lockstep: the Easy enemy made no mistake")


# -------------------------------------------------------------- skilled ---

## Skilled behaviours carried out by sim side `side` (rotations, reserve
## commits and the Skilled-only counters of BattleSim.stat_aic).
static func _skilled(sim, side: int) -> int:
	var n := 0
	for c in [AIProfile.C_ROTATION, AIProfile.C_RESERVE_COMMIT, AIProfile.C_CAV_STAY, AIProfile.C_DOUBLE,
			AIProfile.C_FOCUS, AIProfile.C_GUARD_FREE, AIProfile.C_WAVER_PULL, AIProfile.C_SIEGE, AIProfile.C_ART_PULL]:
		n += sim.stat_aic[side * AIProfile.N_COUNTERS + c]
	return n


## AI battles with a Skilled side: snapshot / restore at several ticks
## runs on exactly.
func _test_skilled_snapshots() -> void:
	for spec in [["battle_2000", [2, 2]], ["siege_city", [2, 1]], ["siege_city", [1, 2]]]:
		var key: String = spec[0]
		var scen: Dictionary = Scenarios.make(key)
		scen["ai_sides"] = [0, 1]
		scen["ai_skill"] = spec[1]
		var a := BattleSim.new()
		a.setup(scen, 31337)
		var bad := 0
		var checks := 0
		for stop in ([600, 1500] if quick else [600, 1500, 2400]):
			while a.tick < stop and a.winner < 0:
				a.step()
			var b := BattleSim.new()
			b.setup(scen, 31337)
			if not b.restore(a.snapshot()) or b.state_hash() != a.state_hash():
				_fail("skilled %s %s: restore at tick %d did not reproduce the hash" % [key, str(spec[1]), stop])
				return
			for t in 200:
				a.step()
				b.step()
				checks += 1
				if a.state_hash() != b.state_hash():
					bad += 1
		var used := _skilled(a, 0) + _skilled(a, 1)
		if bad > 0:
			_fail("skilled %s %s: restored copies diverged (%d of %d ticks)" % [key, str(spec[1]), bad, checks])
		else:
			print("PASS skilled %s %s: snapshot / restore runs on identically (%d ticks checked), Skilled moves %d / %d" % [
				key, str(spec[1]), checks, _skilled(a, 0), _skilled(a, 1)])
		if used == 0:
			_fail("skilled %s %s: no Skilled behaviour was used" % [key, str(spec[1])])


## Two peers (side 0) against a Skilled enemy AI, a third joining
## mid-battle: every frame hash-equal; the enemy used its Skilled moves.
func _test_lockstep_skilled() -> void:
	var scen: Dictionary = Scenarios.make("battle_2000")
	scen["ai_sides"] = [1]
	scen["ai_skill"] = [1, 2]
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
	var total := 1200 if quick else 3000
	var c: Peer = null
	var c_join := total / 3
	var now := 0
	while now < total * 3 and mini(a.ls.frame, b.ls.frame) < total:
		now += 1
		for p in peers:
			_script(p, now, enemy)
			p.flush(relay, now)
			p.deliver(relay, now)
			p.run(p.rng.randi() % 3, true)
		if c != null:
			c.flush(relay, now)
			c.deliver(relay, now)
			c.run(4, true)
		if now == c_join:
			c = _new_peer(scen, home, 1, "C", [0, 1])
			c.online = true
			c.latency = 2
			if not c.ls.restore(a.ls.snapshot()):
				_fail("skilled lockstep: C could not restore A's snapshot")
				return
			c.hashes[c.ls.frame] = c.ls.state_hash()
			c.cursor = 0
			while c.cursor < relay.items.size() and int(relay.items[c.cursor]["s"]) <= c.ls.last_s:
				c.cursor += 1
			c.sent_k = 1 << 30
	var n_ab := _compare(a, b, 0, "skilled A/B")
	var n_ac := _compare(a, c, c_join, "skilled A/C") if c != null else 0
	var used := _skilled(a.ls.sim, 1)
	if n_ab < total / 2 or n_ac < 100:
		_fail("skilled lockstep: too few frames compared (A/B %d, A/C %d)" % [n_ab, n_ac])
	elif n_ab > 0 and n_ac > 0:
		print("PASS skilled lockstep: %d frames A/B and %d A/C equal against a Skilled enemy (sim tick %d, its Skilled moves %d)" % [
			n_ab, n_ac, a.ls.sim.tick, used])
	if used == 0:
		_fail("skilled lockstep: the Skilled enemy used no Skilled behaviour")


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
		p.issue({"type": Lockstep.C_SPEED, "q": [2, 4, 10, 5][p.rng.randi() % 4]})
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
	# Elephants across peers (docs/DESIGN.md "Camels and elephants"): a unit
	# of side 0 behind its line, starting broken (morale 10 %): it runs amok
	# at once; its commander has its drivers kill it (ORDER_KILL) and A's sim
	# is snapshotted while the drivers are at it.
	var el_u: int = (scen["units"] as Array).size()
	scen["units"].append(Scenarios.unit(0, UT.index_of("elephant"), 12, int(scen["width_m"]) / 2,
		int(scen["height_m"]) - 40, Scenarios.FACE_UP))
	scen["units"][el_u]["morale_pct"] = 10
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
	var kill_sent := false
	var kill_snap := -1
	var amok_seen := false
	while now < total * 3 and max_frames < total:
		now += 1
		for p in peers:
			# Different local timing: each peer runs 0-2 frames per clock step.
			if not p.online:
				continue
			_script(p, now, enemy)
			var psim = p.ls.sim
			if psim.u_amok[el_u] != 0:
				amok_seen = true
			if not kill_sent and p.ls.u_cmd[el_u] == p.me and psim.tick > 30 \
					and BattleSim.kill_refusal(psim, el_u) == "":
				p.issue({"type": BattleSim.ORDER_KILL, "unit": el_u})
				kill_sent = true
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
		if kill_snap < 0 and a.ls.sim.u_kill[el_u] > 0 and a.ls.sim.u_kill[el_u] < 40:
			# The drivers at work: two copies restored from A's sim run on equal.
			kill_snap = a.ls.sim.tick
			var kb: PackedByteArray = a.ls.sim.snapshot()
			var k1 := BattleSim.new()
			k1.setup(scen, 4242)
			var k2 := BattleSim.new()
			k2.setup(scen, 4242)
			if not k1.restore(kb) or not k2.restore(kb) or k1.state_hash() != a.ls.sim.state_hash():
				_fail("lockstep: restoring A's sim while the drivers kill the elephants changed its hash")
				return
			for t in 200:
				k1.step()
				k2.step()
				if k1.state_hash() != k2.state_hash():
					_fail("lockstep: copies restored mid-kill diverged after %d ticks" % (t + 1))
					return
			if k1.u_state[el_u] != BattleSim.U_DESTROYED:
				_fail("lockstep: the drivers did not kill the elephants (state %d)" % k1.u_state[el_u])
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
	if not amok_seen or kill_snap < 0 or a.ls.sim.u_state[el_u] != BattleSim.U_DESTROYED \
			or b.ls.sim.u_state[el_u] != BattleSim.U_DESTROYED:
		_fail("lockstep elephants: amok %s, snapshot mid-kill at tick %d, states %d / %d" % [amok_seen, kill_snap,
			a.ls.sim.u_state[el_u], b.ls.sim.u_state[el_u]])
	else:
		print("PASS lockstep elephants: amok from the start, the Kill order through the lockstep, snapshot mid-kill at tick %d ran on equal, dead on both peers" % kill_snap)
	stats["pauses"] = 0
	# Deterministic unit-level checks of the control inputs.
	_check_controls(scen, home)
	_check_speed_vote(scen, home)
	_check_guest(scen, home)


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


## The speed slider's votes: any quarter step 1..16. A proposes 2.5x (q 10,
## not one of the old 0.5 / 1 / 2 / 4x steps), B accepts; both peers apply
## it at the same frame with equal hashes. Out-of-range q is refused.
func _check_speed_vote(scen: Dictionary, home: Array) -> void:
	var peers: Array = []
	for me in [0, 1]:
		var l := Lockstep.new()
		l.setup(scen, 9, home, [0, 1], me)
		peers.append(l)
	var cnt := {0: 0, 1: 0}
	var send := func(p: int, k: int, os: Array) -> void:
		cnt[p] = int(cnt[p]) + 1
		for o in os:
			o["f"] = k
		for l in peers:
			l.receive({"p": p, "n": cnt[p], "k": k, "o": os.duplicate(true)})
	var step := func() -> void:
		for l in peers:
			l.advance()
	var a: Lockstep = peers[0]
	var b: Lockstep = peers[1]
	var rej0: int = a.rejected
	send.call(0, 0, [{"type": Lockstep.C_SPEED, "q": 0}, {"type": Lockstep.C_SPEED, "q": 17}])
	send.call(1, 0, [])
	step.call()
	if a.speed_q != 4 or a.vote_speed_by != -1 or a.rejected != rej0 + 2:
		_fail("an out-of-range speed q was taken")
	send.call(0, 1, [{"type": Lockstep.C_SPEED, "q": 10}])
	send.call(1, 1, [])
	step.call()
	if a.speed_q != 4 or a.vote_speed_by != 0 or a.vote_speed_q != 10 or b.vote_speed_q != 10:
		_fail("A's 2.5x proposal not pending on both (by %d q %d)" % [a.vote_speed_by, a.vote_speed_q])
	send.call(1, 2, [{"type": Lockstep.C_ANSWER, "what": 1, "yes": 1}])
	send.call(0, 2, [])
	step.call()
	if a.speed_q != 10 or b.speed_q != 10 or a.vote_speed_by != -1:
		_fail("B's accept did not apply 2.5x (A q %d, B q %d)" % [a.speed_q, b.speed_q])
	var t0: int = a.sim.tick
	for k in range(3, 23):
		send.call(0, k, [])
		send.call(1, k, [])
		step.call()
		if a.state_hash() != b.state_hash():
			_fail("speed vote: peers diverged at frame %d" % k)
			return
	# 20 frames at 2.5 ticks per frame: 50 ticks.
	if a.sim.tick - t0 != 50:
		_fail("2.5x did not step 2.5 ticks a frame (%d ticks in 20 frames)" % (a.sim.tick - t0))
	print("PASS speed vote: A proposes 2.5x (q 10), B accepts, both apply it at one frame, hashes equal over 20 frames, q 0 / 17 refused")


## A guest (a campaign ally whose army is not in the battle): admitted
## mid-battle, given a unit by the owner, commands it; the owner's order for
## it is refused; nobody else can be given units.
func _check_guest(scen: Dictionary, home: Array) -> void:
	var h0: Array = []
	for x in home:
		h0.append(0 if int(x) >= 0 else int(x))
	var ls := Lockstep.new()
	ls.setup(scen, 9, h0, [0], 0, [3])
	var cnt := {0: 0, 3: 0}
	var send := func(p: int, k: int, os: Array) -> void:
		cnt[p] = int(cnt[p]) + 1
		for o in os:
			o["f"] = k
		ls.receive({"p": p, "n": cnt[p], "k": k, "o": os})
	if ls.is_active(3) or not Array(ls.players).has(3) or ls.side_of(3) != ls.side_of(0) or ls.side_of(5) != -1:
		_fail("guest setup: players %s, active %s, sides %d / %d / %d" % [ls.players, ls.active, ls.side_of(3), ls.side_of(0), ls.side_of(5)])
	var u := -1
	for i in ls.u_cmd.size():
		if ls.u_cmd[i] == 0:
			u = i
			break
	# Not taking part yet: a gift to the guest is refused.
	send.call(0, 0, [{"type": Lockstep.C_GIFT, "unit": u, "to": 3}])
	ls.advance()
	if ls.u_cmd[u] != 0:
		_fail("a gift to a guest not taking part was applied")
	# Admitted at frame 1, then given the unit at frame 2.
	send.call(0, 1, [{"type": Lockstep.C_ADMIT, "who": 3, "keep": 0}])
	ls.advance()
	if not ls.is_active(3):
		_fail("guest not admitted")
	send.call(0, 2, [{"type": Lockstep.C_GIFT, "unit": u, "to": 3}, {"type": Lockstep.C_GIFT, "unit": u + 1, "to": 5}])
	send.call(3, 2, [])
	ls.advance()
	if ls.u_cmd[u] != 3 or ls.u_cmd[u + 1] != 0:
		_fail("gift to the guest: cmd %d (want 3), to an outsider: %d (want 0)" % [ls.u_cmd[u], ls.u_cmd[u + 1]])
	var rej: int = ls.rejected
	send.call(0, 3, [{"type": BattleSim.ORDER_HALT, "unit": u}])
	send.call(3, 3, [{"type": BattleSim.ORDER_HALT, "unit": u}])
	ls.advance()
	if ls.rejected != rej + 1:
		_fail("orders for the guest's unit: %d refused (want 1: the owner's)" % (ls.rejected - rej))
	var ls2 := Lockstep.new()
	ls2.setup(scen, 9, h0, [0], 0, [3])
	if not ls2.restore(ls.snapshot()) or ls2.state_hash() != ls.state_hash():
		_fail("guest: lockstep snapshot round trip changed the hash")
	else:
		print("PASS guest: admitted mid-battle, given a unit, commands it (the owner's order refused), outsiders get nothing, snapshot round trip")


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
		# The quick run is too short for a climb (the march to a stair's foot
		# takes longer): it checks the way down only.
		if polis and def_side == 0 and (sim_a.stat_stair_down == 0 or (sim_a.stat_stair_up == 0 and not quick)):
			_fail("coastal polis (defending): no wall unit went down%s a stair" % ("" if quick else " and up"))


# ------------------------------------------------------ siege equipment ---

## The equal-force walls-3 siege with ladders, a ram and the city's tower
## engines (and a 20 minute time limit), both sides AI: snapshot / restore
## mid-carry (a unit carrying a piece of siege equipment), mid-climb (a unit
## on its ladders with men up and men below) and every 1500 ticks; later
## runs on exactly.
func _test_siege_snapshots() -> void:
	var scen := Scenarios.fair_siege(741, 3, 4, {"ladders": 3, "ram": 1})
	scen["time_limit"] = 1200
	var a := BattleSim.new()
	a.setup(scen, 31337)
	var stops: Array = []
	var climbing := false
	var carrying := false
	while a.tick < 9000 and a.winner < 0 and stops.size() < (3 if quick else 8):
		a.step()
		var mid := -1
		var car := -1
		for u in a.n_units:
			if a.u_carry[u] >= 0 and a.u_state[u] == BattleSim.U_READY:
				car = u
			if a.u_stair[u] == BattleSim.ST_LADDER:
				var up := 0
				var base: int = a.u_slot_base[u]
				for k in a.u_alive[u]:
					var i: int = a.slot_soldier[base + k]
					if a._on_walk(a.pos_x[i], a.pos_y[i]):
						up += 1
				if up > 0 and up < a.u_alive[u]:
					mid = u
		var take := (mid >= 0 and not climbing) or (car >= 0 and not carrying and a.tick > 300) or (a.tick % 1500 == 0)
		if take:
			climbing = climbing or mid >= 0
			carrying = carrying or (car >= 0 and a.tick > 300)
			stops.append(a.tick)
			var b := BattleSim.new()
			b.setup(scen, 31337)
			if not b.restore(a.snapshot()) or b.state_hash() != a.state_hash():
				_fail("siege: restore at tick %d did not reproduce the hash" % a.tick)
				return
			for t in 200:
				a.step()
				b.step()
				if a.state_hash() != b.state_hash():
					_fail("siege: the restored copy diverged %d ticks after tick %d" % [t + 1, stops[-1]])
					return
	if not carrying:
		_fail("siege: no snapshot was taken mid-carry (%s) or mid-climb (%s)" % [str(carrying), str(climbing)])
		return
	print("PASS siege snapshots: walls 3 with ladders, a ram and tower engines; restored at ticks %s (mid-carry, mid-climb %s) and ran on identically; picked up %d, planted %d, men up ladders %d, ram blows %d, tower hits %d" % [
		str(stops), str(climbing), a.stat_pickups, a.stat_planted, a.stat_ladder_up, a.stat_ram_blows, a.stat_tower_hits])


## Two peers attacking the walls-3 city with siege equipment (the
## defenders AI, with the city's tower engines; a 20 minute time limit):
## A's first infantry picks up a ladder set and puts it down again; B's
## second infantry picks that set up and plants it on the stretch nearest
## (climbing it); B's first foot carries the ram to the main gate. A third
## peer joins by snapshot while B carries the ladders A dropped. Every
## frame's lockstep hash must agree.
func _test_lockstep_siege() -> void:
	var scen := Scenarios.fair_siege(741, 3, 4, {"ladders": 3, "ram": 1})
	scen["time_limit"] = 1200
	scen["ai_sides"] = [1]
	# Ammunition kinds and the wagon across peers: an archer unit of side 0
	# carrying fire arrows, a quarter of its load left, with a one-horse
	# wagon beside it; its commander switches it to fire arrows, then has it
	# refill at the wagon (docs/DESIGN.md "Ammunition kinds", "The
	# ammunition wagon").
	var a0: Dictionary = {}
	for ud in scen["units"]:
		if int(ud["side"]) == 0:
			a0 = ud
			break
	var arch2: int = (scen["units"] as Array).size()
	var au := Scenarios.unit(0, UT.ARCHER, 40, int(a0["x_m"]) + 30, int(a0["y_m"]) + (25 if int(a0["facing"]) == Scenarios.FACE_UP else -25), int(a0["facing"]))
	au["ak"] = UT.ammo_index("fire_arrows")
	au["ammo_pct"] = 25
	var wu := Scenarios.unit(0, UT.index_of("wagon2"), 8, int(a0["x_m"]) + 30, int(a0["y_m"]) + (36 if int(a0["facing"]) == Scenarios.FACE_UP else -36), int(a0["facing"]))
	wu["aks"] = [UT.ammo_index("fire_arrows")]
	scen["units"].append(au)
	scen["units"].append(wu)
	var probe := BattleSim.new()
	probe.setup(scen, 4242)
	var home := _home_split(probe)
	var relay := Relay.new()
	var a := _new_peer(scen, home, 0, "A", [0, 1])
	var b := _new_peer(scen, home, 1, "B", [0, 1])
	a.latency = 1
	b.latency = 3
	b.d = 4
	var peers: Array[Peer] = [a, b]
	var total := 1500 if quick else 4500
	var c: Peer = null
	var c_join := -1
	var now := 0
	var orders := 0
	var dropped := false
	var a_carry_t := -1
	var b_carried := false
	var ram_q := -1
	for q in probe.n_eq:
		if probe.q_kind[q] == BattleSim.EQ_RAM:
			ram_q = q
	# Engines as equipment across peers: B leaves its bolt battery's engines,
	# A's archers take them up and later leave them.
	var bat := -1
	var arch := -1
	for u in probe.n_units:
		if probe.u_side[u] == 0 and bat < 0 and probe.u_type[u] == UT.BOLT:
			bat = u
		if probe.u_side[u] == 0 and arch < 0 and probe.u_type[u] == UT.ARCHER and int(home[u]) != int(home[bat]):
			arch = u
	var eg: int = probe.u_eg[bat]
	var e_left := false
	var a_eng_t := -1
	var a_eng_done := false
	var e_stage := 0  # snapshots of A's sim: 1 on the way to the engines, 2 working them, 3 left again
	var e_snaps: Array = []
	var k_sent := false
	var r_sent := false
	var r_snap := -1
	while now < total * 3 and mini(a.ls.frame, b.ls.frame) < total:
		now += 1
		for p in peers:
			var sim = p.ls.sim
			if p.ls.u_cmd[arch2] == p.me and now % 20 == 11:
				if not k_sent and sim.tick > 40:
					p.issue({"type": BattleSim.ORDER_AMMO, "unit": arch2, "on": 1})
					k_sent = true
					orders += 1
				elif k_sent and not r_sent and sim.tick > 90 and sim.u_akind[arch2] == 1:
					p.issue({"type": BattleSim.ORDER_REFILL, "unit": arch2, "on": 1})
					r_sent = true
					orders += 1
			if now % 20 == 9 + p.me * 5 and arch >= 0:
				if p.ls.u_cmd[bat] == p.me and not e_left and sim.tick > 150 and sim.u_eg[bat] == eg \
						and sim.u_state[bat] == BattleSim.U_READY:
					p.issue({"type": BattleSim.ORDER_DROP, "unit": bat})
					e_left = true
					orders += 1
				if p.ls.u_cmd[arch] == p.me and sim.u_state[arch] == BattleSim.U_READY and sim.engines_free(eg) \
						and sim.u_eg[bat] < 0 and not a_eng_done and sim.u_pick[arch] != BattleSim.PICK_ENG + eg:
					p.issue({"type": BattleSim.ORDER_PICKUP, "unit": arch, "engines": eg, "run": 1})
					orders += 1
				elif p.ls.u_cmd[arch] == p.me and sim.u_eg[arch] == eg:
					if a_eng_t < 0:
						a_eng_t = now
					elif now - a_eng_t > 300 and not a_eng_done:
						p.issue({"type": BattleSim.ORDER_DROP, "unit": arch})
						a_eng_done = true
						orders += 1
			if now % 20 == 5 + p.me * 7:
				var mine: Array = []
				for u in sim.n_units:
					if p.ls.u_cmd[u] == p.me and sim.u_state[u] == BattleSim.U_READY and sim.u_cls[u] == UT.CLS_INF \
							and sim.u_otype[u] == sim.u_type[u]:
						mine.append(u)  # (not the battery that left its engines)
				if mine.size() < 2:
					continue
				if p.me == 0:
					var ua: int = mine[0]
					if not dropped and sim.u_carry[ua] < 0 and sim.q_state[0] == BattleSim.Q_GROUND and sim.u_pick[ua] != 0:
						p.issue({"type": BattleSim.ORDER_PICKUP, "unit": ua, "equip": 0, "run": 1})
						orders += 1
					elif sim.u_carry[ua] == 0:
						if a_carry_t < 0:
							a_carry_t = now
						elif now - a_carry_t > 150 and not dropped:
							p.issue({"type": BattleSim.ORDER_DROP, "unit": ua})
							dropped = true
							orders += 1
				else:
					var ur: int = mine[0]
					var ub: int = mine[1]
					if ram_q >= 0 and sim.u_carry[ur] < 0 and sim.q_state[ram_q] == BattleSim.Q_GROUND and sim.u_pick[ur] != ram_q:
						p.issue({"type": BattleSim.ORDER_PICKUP, "unit": ur, "equip": ram_q, "run": 1})
						orders += 1
					elif sim.u_carry[ur] == ram_q and sim.u_gtarget[ur] != 0 and sim.g_state[0] == BattleSim.GATE_CLOSED:
						p.issue({"type": BattleSim.ORDER_ATTACK, "unit": ur, "target": -1, "gate": 0, "run": 0})
						orders += 1
					if dropped and sim.u_carry[ub] < 0 and sim.q_state[0] == BattleSim.Q_GROUND and sim.u_pick[ub] != 0:
						p.issue({"type": BattleSim.ORDER_PICKUP, "unit": ub, "equip": 0, "run": 1})
						orders += 1
					elif sim.u_carry[ub] == 0 and sim.u_stair[ub] == 0:
						b_carried = true
						var best := -1
						var bd := 0
						for sg in sim.ws_x0.size():
							var mp: Vector2i = BattleSim.seg_pt(sim, sg, BattleSim.seg_len(sim, sg) / 2)
							if BattleSim.ladder_set_for(sim, ub, sg, mp.x, mp.y) < 0:
								continue
							var d := absi(mp.x - sim.u_cx[ub]) + absi(mp.y - sim.u_cy[ub])
							if best < 0 or d < bd:
								best = sg
								bd = d
						if best >= 0 and (sim.u_order[ub] != BattleSim.O_MOVE or sim.u_stair[ub] == 0):
							var lp: Vector2i = BattleSim.seg_pt(sim, best, BattleSim.seg_len(sim, best) / 2)
							p.issue({"type": BattleSim.ORDER_MOVE, "unit": ub, "x": lp.x, "y": lp.y, "facing": 768,
								"width": 20 * 1024, "run": 0})
							orders += 1
			p.flush(relay, now)
			p.deliver(relay, now)
			p.run(p.rng.randi() % 3, true)
		# Snapshot / restore across the pick-up and the drop: two copies of
		# A's sim restored from it run on equal.
		var sa = a.ls.sim
		var e_take := false
		if e_stage == 0 and sa.u_pick[arch] == BattleSim.PICK_ENG + eg:
			e_stage = 1
			e_take = true
		elif e_stage == 1 and sa.u_eg[arch] == eg and a_eng_t >= 0 and now - a_eng_t >= 60:
			e_stage = 2
			e_take = true
		elif e_stage == 2 and a_eng_done and sa.u_eg[arch] < 0:
			e_stage = 3
			e_take = true
		if r_snap < 0 and sa.u_rprog[arch2] == BattleSim.REFILL_FULL and sa.stat_refill_shots > 0:
			# Mid-refill at the wagon: two restored copies run on equal.
			r_snap = sa.tick
			var rb: PackedByteArray = sa.snapshot()
			var y1 := BattleSim.new()
			y1.setup(scen, 4242)
			var y2 := BattleSim.new()
			y2.setup(scen, 4242)
			if not y1.restore(rb) or not y2.restore(rb) or y1.state_hash() != sa.state_hash():
				_fail("siege lockstep: restoring A's sim mid-refill did not reproduce its hash")
				return
			for t in 200:
				y1.step()
				y2.step()
				if y1.state_hash() != y2.state_hash():
					_fail("siege lockstep: copies restored mid-refill diverged after %d ticks" % (t + 1))
					return
		if e_take:
			var blob: PackedByteArray = sa.snapshot()
			var x1 := BattleSim.new()
			x1.setup(scen, 4242)
			var x2 := BattleSim.new()
			x2.setup(scen, 4242)
			if not x1.restore(blob) or not x2.restore(blob) or x1.state_hash() != sa.state_hash():
				_fail("siege lockstep: restoring A's sim at the engines (stage %d) did not reproduce its hash" % e_stage)
				return
			for t in 200:
				x1.step()
				x2.step()
				if x1.state_hash() != x2.state_hash():
					_fail("siege lockstep: copies restored at the engines (stage %d) diverged after %d ticks" % [e_stage, t + 1])
					return
			e_snaps.append(sa.tick)
		if c != null:
			c.flush(relay, now)
			c.deliver(relay, now)
			c.run(4, true)
		elif now > 30 and (b_carried or now == total * 3 / 2):
			c_join = now
			c = _new_peer(scen, home, 1, "C", [0, 1])
			c.online = true
			c.latency = 2
			if not c.ls.restore(a.ls.snapshot()):
				_fail("siege lockstep: C could not restore A's snapshot")
				return
			c.hashes[c.ls.frame] = c.ls.state_hash()
			c.cursor = 0
			while c.cursor < relay.items.size() and int(relay.items[c.cursor]["s"]) <= c.ls.last_s:
				c.cursor += 1
			c.sent_k = 1 << 30
	var n_ab := _compare(a, b, 0, "siege A/B")
	var n_ac := _compare(a, c, c_join, "siege A/C") if c != null else 0
	var sim_a = a.ls.sim
	if n_ab < total / 2 or n_ac < 50:
		_fail("siege lockstep: too few frames compared (A/B %d, A/C %d)" % [n_ab, n_ac])
	elif n_ab > 0 and n_ac > 0:
		print("PASS siege lockstep: walls 3, ladders, a ram, tower engines, 20 min limit: %d frames A/B and %d A/C equal (C joined at frame %d, mid-carry %s); %d siege orders; picked up %d, dropped %d, planted %d, men up ladders %d, ram blows %d, tower hits %d, gates %s; sim tick %d" % [
			n_ab, n_ac, c_join, str(b_carried), orders, sim_a.stat_pickups, sim_a.stat_drops, sim_a.stat_planted,
			sim_a.stat_ladder_up, sim_a.stat_ram_blows, sim_a.stat_tower_hits, str(sim_a.g_state), sim_a.tick])
	if sim_a.stat_epick < 1 or sim_a.stat_edrop < 2 or e_snaps.size() < 3:
		_fail("siege lockstep: the engines were not left by B's battery, taken up and left by A's archers with snapshots on the way (%d / %d, snapshots at %s)" % [
			sim_a.stat_epick, sim_a.stat_edrop, str(e_snaps)])
	else:
		print("PASS siege lockstep engines: B's battery left them, A's archers took them up and left them (taken up %d, left %d), hashes equal; snapshot / restore on the way to them, while working them and once left (ticks %s) ran on identically" % [
			sim_a.stat_epick, sim_a.stat_edrop, str(e_snaps)])
	if not k_sent or not r_sent or r_snap < 0 or sim_a.stat_refill_shots <= 0 or sim_a.u_akind[arch2] != 1:
		_fail("siege lockstep: the archers' kind switch / wagon refill did not happen (sent %s %s, snapshot %d, shots %d)" % [
			str(k_sent), str(r_sent), r_snap, sim_a.stat_refill_shots])
	else:
		print("PASS siege lockstep kinds and wagon: archers switched to fire arrows, refilled %d missiles at the wagon; hashes equal; snapshot / restore mid-refill (tick %d) ran on identically" % [
			sim_a.stat_refill_shots, r_snap])
	if sim_a.stat_pickups < 3 or sim_a.stat_drops < 1 or not b_carried:
		_fail("siege lockstep: the equipment was not picked up, dropped and picked up again (%d / %d)" % [
			sim_a.stat_pickups, sim_a.stat_drops])
	elif not quick and sim_a.stat_planted == 0:
		_fail("siege lockstep: the ladders were never planted")


# -------------------------------------------------------------- blocking ---

## Two peers (side 0, three heavy units in a 10 m street) against the AI's
## three coming down it; each peer sends its units at the enemy unit
## nearest them now and then; a third peer joins by snapshot once units
## are waiting behind friends who fight (the street fight under way).
func _test_lockstep_street() -> void:
	var units: Array = []
	for k in 3:
		units.append(Scenarios.unit(0, UT.HEAVY, 60, 150, 252 + k * 16, Scenarios.FACE_UP))
	for k in 3:
		units.append(Scenarios.unit(1, UT.HEAVY, 60, 150, 48 - k * 16, Scenarios.FACE_DOWN))
	for u in units:
		u["files"] = 8
	var scen := {"width_m": 300, "height_m": 300, "units": units, "ai_sides": [1],
		"terrain": {"kind": 0, "blocks": [[40, 60, 145, 240], [155, 60, 260, 240]], "urban": [[40, 60, 260, 240]]}}
	var probe := BattleSim.new()
	probe.setup(scen, 4242)
	var home := _home_split(probe)
	var relay := Relay.new()
	var a := _new_peer(scen, home, 0, "A", [0, 1])
	var b := _new_peer(scen, home, 1, "B", [0, 1])
	a.latency = 1
	b.latency = 3
	b.d = 4
	var peers: Array[Peer] = [a, b]
	# Not shortened by --quick: the columns meet and C joins after frame 900.
	var total := 1800
	var c: Peer = null
	var c_join := -1
	var now := 0
	while now < total * 3 and mini(a.ls.frame, b.ls.frame) < total:
		now += 1
		for p in peers:
			var sim = p.ls.sim
			if now % 40 == 5 + p.me * 13:
				for u in sim.n_units:
					if p.ls.u_cmd[u] != p.me or sim.u_state[u] != BattleSim.U_READY or sim.u_order[u] == BattleSim.O_ATTACK:
						continue
					var best := -1
					var bd := 0
					for o in sim.n_units:
						if sim.u_side[o] == 1 and sim.u_state[o] == BattleSim.U_READY:
							var d: int = absi(sim.u_cx[o] - sim.u_cx[u]) + absi(sim.u_cy[o] - sim.u_cy[u])
							if best < 0 or d < bd:
								best = o
								bd = d
					if best >= 0:
						p.issue({"type": BattleSim.ORDER_ATTACK, "unit": u, "target": best, "run": 0})
			p.flush(relay, now)
			p.deliver(relay, now)
			p.run(p.rng.randi() % 3, true)
		if c != null:
			c.flush(relay, now)
			c.deliver(relay, now)
			c.run(4, true)
		elif now > 30:
			var sa = a.ls.sim
			var fighting := false
			for u in sa.n_units:
				if sa.u_fighting[u] > 0:
					fighting = true
			if (fighting and sa.stat_queued > 20) or now == total * 3 / 2:
				c_join = now
				c = _new_peer(scen, home, 1, "C", [0, 1])
				c.online = true
				c.latency = 2
				if not c.ls.restore(a.ls.snapshot()):
					_fail("street lockstep: C could not restore A's snapshot")
					return
				c.hashes[c.ls.frame] = c.ls.state_hash()
				c.cursor = 0
				while c.cursor < relay.items.size() and int(relay.items[c.cursor]["s"]) <= c.ls.last_s:
					c.cursor += 1
				c.sent_k = 1 << 30
	var n_ab := _compare(a, b, 0, "street A/B")
	var n_ac := _compare(a, c, c_join, "street A/C") if c != null else 0
	var sim_a = a.ls.sim
	if n_ab < total / 2 or n_ac < 50:
		_fail("street lockstep: too few frames compared (A/B %d, A/C %d)" % [n_ab, n_ac])
	elif n_ab > 0 and n_ac > 0:
		print("PASS street lockstep: %d frames A/B and %d A/C equal (C joined at frame %d, mid street fight %s); waited behind friends %d, stopped at enemies %d, through friends %d; killed %d / %d; sim tick %d" % [
			n_ab, n_ac, c_join, str(c_join != total * 3 / 2), sim_a.stat_queued, sim_a.stat_blocked, sim_a.stat_pass,
			sim_a.u_killed[0] + sim_a.u_killed[1] + sim_a.u_killed[2], sim_a.u_killed[3] + sim_a.u_killed[4] + sim_a.u_killed[5], sim_a.tick])
	if sim_a.stat_queued == 0:
		_fail("street lockstep: nobody waited behind a fighting friend")


# ------------------------------------------------------------ deployment ---

## Two peers through the relay in a battle with a deployment phase.
## mode "coop": both on side 0 against the AI; A ready early, B later; a
##   third peer joins by snapshot during the deployment.
## mode "h2h": head-to-head (A side 0, B side 1, no AI); nobody readies
##   but A: the countdown starts the battle; then B drops (A is an enemy:
##   the AI takes B's side), comes back and is admitted (the AI hands it
##   back); gifts to the enemy refused.
## mode "h2h_drop": head-to-head, A ready early, B drops during the
##   deployment: the battle starts without waiting for B.
func _test_deploy(mode: String) -> void:
	var scen: Dictionary = Scenarios.make("battle_2000")
	scen["terrain"] = {"kind": 2, "seed": 5}
	scen["deploy_time"] = 40
	scen["deploy_zones"] = Scenarios.field_zones(scen)
	var h2h := mode != "coop"
	scen["ai_sides"] = [] if h2h else [1]
	var probe := BattleSim.new()
	probe.setup(scen, 4242)
	var home: Array = []
	if h2h:
		for u in probe.n_units:
			home.append(probe.u_side[u])
	else:
		home = _home_split(probe)
	var relay := Relay.new()
	var a := _new_peer(scen, home, 0, "A", [0, 1])
	var b := _new_peer(scen, home, 1, "B", [0, 1])
	a.latency = 1
	b.latency = 3
	b.d = 4
	var peers: Array[Peer] = [a, b]
	var c: Peer = null
	var start_frame := {}
	var placed := {"A": 0, "B": 0}
	var refused0: int = a.ls.rejected
	var now := 0
	var b_drop := 80 if mode == "h2h_drop" else (600 if mode == "h2h" else -1)
	var b_back := b_drop + 60 if mode == "h2h" else -1
	var ai_took := false
	var ai_gave := false
	var total := 900
	while now < total * 3 and a.ls.frame < total:
		now += 1
		for p in peers:
			if not p.online:
				continue
			var sim = p.ls.sim
			if sim.phase == BattleSim.PHASE_DEPLOY:
				if sim.tick != 0:
					_fail("%s %s: the sim clock ran during the deployment" % [mode, p.name])
				if now % 5 == p.me and now < 200:
					# Place one of my units somewhere in our half (clamped), and
					# try one of the other's (refused).
					var mine: Array = []
					var theirs: Array = []
					for u in sim.n_units:
						if p.ls.u_cmd[u] == p.me:
							mine.append(u)
						elif p.ls.u_cmd[u] >= 0:
							theirs.append(u)
					if not mine.is_empty():
						var u: int = mine[p.rng.randi() % mine.size()]
						p.issue({"type": BattleSim.ORDER_PLACE, "unit": u, "x": sim.u_ax[u] + (p.rng.randi() % 61 - 30) * 1024,
							"y": sim.u_ay[u] + (p.rng.randi() % 61 - 30) * 1024, "facing": sim.u_face[u], "files": 8 + p.rng.randi() % 10})
						placed[p.name] = int(placed[p.name]) + 1
					if not theirs.is_empty() and now % 20 == p.me:
						p.issue({"type": BattleSim.ORDER_PLACE, "unit": theirs[0], "x": 10 * 1024, "y": 10 * 1024,
							"facing": 0, "files": 8})
						if h2h:
							# A gift to the enemy: refused.
							p.issue({"type": Lockstep.C_GIFT, "unit": mine[0], "to": 1 - p.me})
				var ready_at := 30 if p.me == 0 else (120 if mode == "coop" else -1)
				if now == ready_at:
					p.issue({"type": BattleSim.ORDER_READY})
			elif not start_frame.has(p.name):
				start_frame[p.name] = p.ls.frame
			elif now % 9 == p.me:
				_script(p, now, [])
			p.flush(relay, now)
			p.deliver(relay, now)
			p.run(p.rng.randi() % 3, true)
		if c != null:
			c.flush(relay, now)
			c.deliver(relay, now)
			c.run(4, true)
		if mode == "coop" and now == 60:
			# A third peer (B's seat on another device) joins during the deployment.
			c = _new_peer(scen, home, 1, "C", [0, 1])
			if not c.ls.restore(a.ls.snapshot()) or c.ls.state_hash() != a.ls.state_hash():
				_fail("deploy coop: C could not restore A's snapshot taken during the deployment")
				return
			if c.ls.sim.phase != BattleSim.PHASE_DEPLOY:
				_fail("deploy coop: the snapshot lost the deployment phase")
			c.hashes[c.ls.frame] = c.ls.state_hash()
			c.cursor = 0
			while c.cursor < relay.items.size() and int(relay.items[c.cursor]["s"]) <= c.ls.last_s:
				c.cursor += 1
			c.sent_k = 1 << 30
		if now == b_drop:
			b.online = false
			relay.drop(now, 1, 0)
		if mode == "h2h" and b_drop > 0 and now > b_drop and now < b_back and not ai_took:
			if a.ls.sim.ai_sides[1] != 0 and not a.ls.is_active(1):
				ai_took = true
				for u in a.ls.u_cmd.size():
					if a.ls.sim.u_side[u] == 1 and a.ls.u_cmd[u] != -1:
						_fail("h2h: a dropped enemy's unit went to the other player")
						break
		if now == b_back:
			var nb := _new_peer(scen, home, 1, "B", [0, 1])
			nb.latency = b.latency
			nb.d = b.d
			if not nb.ls.restore(a.ls.snapshot()):
				_fail("h2h: B could not restore after reconnecting")
				return
			nb.cursor = 0
			while nb.cursor < relay.items.size() and int(relay.items[nb.cursor]["s"]) <= nb.ls.last_s:
				nb.cursor += 1
			nb.n = int(relay.last_n.get(1, 0))
			nb.sent_k = int(relay.last_k.get(1, -1))
			nb.hashes = b.hashes
			relay.dropped.erase(1)
			b = nb
			peers[1] = b
			a.issue({"type": Lockstep.C_ADMIT, "who": 1, "keep": 0})
		if mode == "h2h" and now > b_back and b_back > 0 and not ai_gave and a.ls.is_active(1):
			ai_gave = a.ls.sim.ai_sides[1] == 0
	var n_ab := _compare(a, b, 0, "deploy %s A/B" % mode)
	var n_ac := _compare(a, c, 60, "deploy %s A/C" % mode) if c != null else 0
	var sf: int = start_frame.get("A", -1)
	var why := ""
	match mode:
		"coop":
			# B's ready (issued at clock 120) starts it, before the countdown (400).
			if sf < 100 or sf > 300:
				_fail("deploy coop: the battle started at frame %d (want after B's ready, before the countdown)" % sf)
			if c == null or n_ac < 100:
				_fail("deploy coop: too few frames compared for the joiner (%d)" % n_ac)
			why = "started at frame %d on both readies; C joined during the deployment (%d frames equal)" % [sf, n_ac]
		"h2h":
			if sf < 395 or sf > 410:
				_fail("deploy h2h: the countdown did not start the battle (frame %d)" % sf)
			if not ai_took:
				_fail("deploy h2h: the AI did not take over the dropped enemy's side")
			if not ai_gave:
				_fail("deploy h2h: the AI did not hand the side back on admission")
			if a.ls.rejected <= refused0:
				_fail("deploy h2h: no refusal (placing the enemy's units, gifts to the enemy)")
			why = "countdown started it at frame %d; B dropped: the AI took side 1, gave it back on admission; %d inputs refused" % [sf, a.ls.rejected]
		"h2h_drop":
			if sf < 40 or sf > 140:
				_fail("deploy h2h_drop: the battle did not start when B dropped (frame %d)" % sf)
			if a.ls.sim.ai_sides[1] == 0:
				_fail("deploy h2h_drop: the AI did not take B's side")
			why = "started at frame %d when the unready B dropped; the AI fights side 1" % sf
	# (The same start frame on both is implied by the hashes, which hold
	# the phase: start_frame is only when each peer's loop noticed it.)
	if n_ab < (60 if mode == "h2h_drop" else 300):
		_fail("deploy %s: too few frames compared (%d)" % [mode, n_ab])
	if int(placed["A"]) == 0 or int(placed["B"]) == 0:
		_fail("deploy %s: nothing placed" % mode)
	print("PASS deploy %s: %d frames equal A/B; %s; placements A %d B %d" % [mode, n_ab, why, int(placed["A"]), int(placed["B"])])
