extends RefCounted
## Deterministic lockstep layer for live co-op battles (milestone 5). Pure
## logic, no networking: game/net/coop_session.gd feeds it the relay's
## message stream and drives it; tests feed it directly.
##
## Time is counted in lockstep frames at 10 Hz of wall time. Every input
## (a sim order or a control order) carries the frame it executes on ("f"),
## chosen by its issuer a few frames ahead. Each player's inputs arrive in
## numbered messages {p, n, k, o: [...]}: "k" (the mark) promises that the
## player will send no more inputs for frames <= k. A frame may only be
## processed when every participating player's mark has reached it, so every
## peer applies exactly the same inputs on exactly the same frame, sorted by
## (f, player, message number, index). Own messages are applied when sent
## (no round trip), others' when they arrive; duplicates are dropped by
## message number, so replaying a stream is harmless.
##
## A frame applies its inputs, then (unless paused) adds the speed to an
## accumulator in quarter ticks and steps the sim once per 4 (0.5x: every
## other frame; 4x: four steps), so pause and speed are lockstep state too.
##
## Lockstep state that every peer must agree on is hashed together with the
## sim (state_hash()): frame, pause / speed and their pending votes, who
## takes part, and the command table (which player commands each unit, and
## for whom a unit is held while its player is away). Inputs not yet due,
## marks and message counters are receipt state: they are in snapshots but
## not in the hash (peers legitimately differ in what they have received).
##
## Command rules (checked when an input is applied, so every peer rejects
## the same inputs): a sim order for a unit counts only from the player who
## commands that unit at that frame; an army withdrawal withdraws only the
## issuer's units; a player not taking part cannot order anything.
## Control inputs: pause / speed requests and answers (a vote: a request
## needs the other player's agreement unless only one player takes part),
## gifting a unit to another player, admitting a (re)joining player, and the
## server's drop event (a disconnected or leaving player: their units go to
## the player named in the event, held for them until they are admitted
## again).

const BattleSim := preload("res://sim/battle_sim.gd")

const FRAME_HZ := 10
const Q_TICK := 4                 # quarter ticks per sim tick
const SPEED_QS := [2, 4, 8, 16]   # 0.5x, 1x, 2x, 4x
const SERVER := 250               # player id of server events

# Control input types (sim order types are 1..10).
const C_PAUSE := 101    # want: 1 pause, 0 resume
const C_SPEED := 102    # q: one of SPEED_QS
const C_ANSWER := 103   # what: 0 pause / 1 speed, yes: 1 / 0
const C_GIFT := 104     # unit, to
const C_ADMIT := 105    # who, keep (1: units held for them stay where they are)
const S_DROP := 120     # who, to (server event)

const _MAGIC := 0x314B534C  # "LSK1"

var sim  # BattleSim

# ---- hashed state ----
var frame := 0
var acc := 0
var speed_q := 4
var paused := 0
var vote_pause_by := -1
var vote_pause_want := 0
var vote_speed_by := -1
var vote_speed_q := 0
var players := PackedInt32Array()   # every human player of the battle, ascending
var active := PackedInt32Array()    # per players[i]: 1 while taking part
var u_cmd := PackedInt32Array()     # unit -> commanding player (-1: not a human's)
var u_away := PackedInt32Array()    # unit -> player it is held for (-1: none)
var u_home := PackedInt32Array()    # unit -> player who commands it by default

# ---- receipt state (snapshotted, not hashed) ----
var queue: Array = []        # inputs not yet applied: {f, p, n, i, type, ...}
var marks := {}              # player -> mark (inputs complete through this frame)
var last_n := {}             # player -> last message number applied
var drop_at := {}            # player -> frame from which they are not awaited
var last_s := 0              # last relay sequence number processed

# ---- diagnostics (not state) ----
var rejected := 0            # inputs refused by the command rules
var late := 0                # inputs for frames already promised (dropped)
var applied := 0


## home[u]: the player who commands unit u by default (-1: enemy / AI).
## present: players taking part from the first frame; units of the others
## start with `host`, held for them until they are admitted.
func setup(scenario: Dictionary, p_seed: int, home: Array, present: Array, host: int) -> void:
	sim = BattleSim.new()
	sim.setup(scenario, p_seed)
	frame = 0
	acc = 0
	speed_q = 4
	paused = 0
	_clear_votes()
	var ps: Array[int] = []
	for h in home:
		if int(h) >= 0 and not ps.has(int(h)):
			ps.append(int(h))
	for p in present:
		if not ps.has(int(p)):
			ps.append(int(p))
	if host >= 0 and not ps.has(host):
		ps.append(host)
	ps.sort()
	players = PackedInt32Array(ps)
	active = PackedInt32Array()
	active.resize(players.size())
	for i in players.size():
		active[i] = 1 if present.has(players[i]) else 0
	var n_units: int = sim.n_units
	u_cmd = PackedInt32Array()
	u_away = PackedInt32Array()
	u_home = PackedInt32Array()
	u_cmd.resize(n_units)
	u_away.resize(n_units)
	u_home.resize(n_units)
	for u in n_units:
		var h := int(home[u]) if u < home.size() else -1
		u_home[u] = h
		u_away[u] = -1
		if h < 0:
			u_cmd[u] = -1
		elif is_active(h):
			u_cmd[u] = h
		else:
			u_cmd[u] = host
			u_away[u] = h
	queue = []
	marks = {}
	last_n = {}
	drop_at = {}
	last_s = 0
	for p in players:
		marks[p] = -1
		last_n[p] = 0


func is_active(p: int) -> bool:
	var i := players.find(p)
	return i >= 0 and active[i] != 0


func active_count() -> int:
	var c := 0
	for a in active:
		c += a
	return c


func active_players() -> Array[int]:
	var out: Array[int] = []
	for i in players.size():
		if active[i] != 0:
			out.append(players[i])
	return out


func commander(u: int) -> int:
	return u_cmd[u] if u >= 0 and u < u_cmd.size() else -1


# ------------------------------------------------------------- receiving ---

## A player's message {p, n, k, o: [inputs with "f" and "type"]}. Returns
## "ok", "dup" (already applied: ignored) or "gap" (a message is missing:
## the caller must resync).
func receive(msg: Dictionary) -> String:
	var p := int(msg.get("p", -1))
	var n := int(msg.get("n", 0))
	if p < 0 or p >= SERVER:
		return "bad"
	var ln := int(last_n.get(p, 0))
	if n <= ln:
		return "dup"
	if n != ln + 1:
		return "gap"
	last_n[p] = n
	var prev_mark := int(marks.get(p, -1))
	var k := int(msg.get("k", prev_mark))
	var orders = msg.get("o", [])
	if orders is Array:
		var i := 0
		for o in orders:
			if not (o is Dictionary):
				continue
			var d := {}
			for key in o:
				d[str(key)] = int(o[key])
			d["p"] = p
			d["n"] = n
			d["i"] = i
			i += 1
			var f := int(d.get("f", -1))
			# An input for a frame its issuer had already promised is a
			# protocol violation; every peer drops it alike.
			if f <= prev_mark or f > k:
				late += 1
				continue
			queue.append(d)
	if k > prev_mark:
		marks[p] = k
	return "ok"


## A relay event {s, t: "drop", who, after, to}: `who` is not awaited after
## frame `after`; from frame after + 1 their units go to `to`.
func receive_event(ev: Dictionary) -> String:
	var s := int(ev.get("s", 0))
	if s > 0 and s <= last_s:
		return "dup"
	if str(ev.get("t", "")) == "drop":
		var who := int(ev.get("who", -1))
		var after := int(ev.get("after", -1))
		if players.find(who) < 0:
			return "bad"
		# Never in a frame already processed (the relay computes `after`
		# from the last mark it passed on, which nobody can be past).
		var f := maxi(after + 1, frame)
		drop_at[who] = f
		queue.append({"f": f, "p": SERVER, "n": s, "i": 0, "type": S_DROP, "who": who,
			"to": int(ev.get("to", -1))})
	return "ok"


## Remember the relay sequence number of the last stream item processed.
func saw(s: int) -> void:
	last_s = maxi(last_s, s)


## Players whose inputs for the current frame are still missing.
func waiting_for() -> Array[int]:
	var out: Array[int] = []
	for i in players.size():
		var p := players[i]
		if active[i] == 0:
			continue
		if int(marks.get(p, -1)) >= frame:
			continue
		if drop_at.has(p) and int(drop_at[p]) <= frame:
			continue
		out.append(p)
	return out


func can_advance() -> bool:
	return waiting_for().is_empty()


## Highest mark of any player but `me` (-1 if none).
func max_mark(me: int = -1) -> int:
	var m := -1
	for p in marks:
		if int(p) != me:
			m = maxi(m, int(marks[p]))
	return m


# ------------------------------------------------------------ processing ---

static func _input_less(a: Dictionary, b: Dictionary) -> bool:
	if int(a["f"]) != int(b["f"]):
		return int(a["f"]) < int(b["f"])
	if int(a["p"]) != int(b["p"]):
		return int(a["p"]) < int(b["p"])
	if int(a["n"]) != int(b["n"]):
		return int(a["n"]) < int(b["n"])
	return int(a["i"]) < int(b["i"])


## Process one frame (call only when can_advance()). Returns the number of
## sim ticks stepped (0 while paused or at 0.5x on alternate frames).
func advance() -> int:
	if not queue.is_empty():
		var due: Array = []
		var rest: Array = []
		for o in queue:
			if int(o["f"]) <= frame:
				due.append(o)
			else:
				rest.append(o)
		if not due.is_empty():
			queue = rest
			due.sort_custom(_input_less)
			for o in due:
				_apply(o)
	var steps := 0
	if paused == 0:
		acc += speed_q
		while acc >= Q_TICK:
			sim.step()
			acc -= Q_TICK
			steps += 1
	frame += 1
	return steps


func _apply(o: Dictionary) -> void:
	var p := int(o["p"])
	var typ := int(o.get("type", 0))
	if p == SERVER:
		if typ == S_DROP:
			_drop(int(o.get("who", -1)), int(o.get("to", -1)))
		return
	if typ == C_ADMIT:
		var who := int(o.get("who", -1))
		# Normally the host admits; a lone player may admit themselves when
		# nobody takes part any more.
		if is_active(p) or (active_count() == 0 and who == p):
			_admit(who, int(o.get("keep", 0)))
			applied += 1
		else:
			rejected += 1
		return
	if not is_active(p):
		rejected += 1
		return
	applied += 1
	match typ:
		C_PAUSE:
			_vote_pause(p, 1 if int(o.get("want", 1)) != 0 else 0)
		C_SPEED:
			var q := int(o.get("q", 4))
			if SPEED_QS.has(q):
				_vote_speed(p, q)
		C_ANSWER:
			_answer(p, int(o.get("what", 0)), int(o.get("yes", 0)) != 0)
		C_GIFT:
			var u := int(o.get("unit", -1))
			var to := int(o.get("to", -1))
			if u >= 0 and u < u_cmd.size() and u_cmd[u] == p and to != p and is_active(to):
				u_cmd[u] = to
				u_away[u] = -1
			else:
				rejected += 1
				applied -= 1
		_:
			if typ >= BattleSim.ORDER_MOVE and typ <= BattleSim.ORDER_REFILL:
				_sim_order(p, o)
			else:
				rejected += 1
				applied -= 1


## A sim order from player p, if p commands the unit(s); fed to the sim for
## its next step with a canonical (player, seq).
func _sim_order(p: int, o: Dictionary) -> void:
	var typ := int(o["type"])
	var seq := int(o["n"]) * 64 + int(o["i"])
	if typ == BattleSim.ORDER_WITHDRAW_ALL:
		# Army withdrawal: the issuer's own units only.
		for u in u_cmd.size():
			if u_cmd[u] == p and sim.u_state[u] == BattleSim.U_READY:
				sim.queue_order({"tick": sim.tick, "type": BattleSim.ORDER_WITHDRAW, "unit": u,
					"player": p, "seq": seq})
		return
	var u := int(o.get("unit", -1))
	if u < 0 or u >= u_cmd.size() or u_cmd[u] != p:
		rejected += 1
		applied -= 1
		return
	var d := {}
	for key in o:
		if key in ["f", "p", "n", "i"]:
			continue
		d[key] = o[key]
	d["tick"] = sim.tick
	d["player"] = p
	d["seq"] = seq
	sim.queue_order(d)


func _clear_votes() -> void:
	vote_pause_by = -1
	vote_pause_want = 0
	vote_speed_by = -1
	vote_speed_q = 0


func _vote_pause(p: int, want: int) -> void:
	if want == paused:
		if vote_pause_by >= 0 and vote_pause_want == want:
			vote_pause_by = -1
		return
	if active_count() <= 1 or (vote_pause_by >= 0 and vote_pause_by != p and vote_pause_want == want):
		paused = want
		vote_pause_by = -1
		return
	if vote_pause_by == p and vote_pause_want == want:
		vote_pause_by = -1  # asked again: withdrawn
		return
	vote_pause_by = p
	vote_pause_want = want


func _vote_speed(p: int, q: int) -> void:
	if q == speed_q:
		if vote_speed_by >= 0 and vote_speed_q == q:
			vote_speed_by = -1
		return
	if active_count() <= 1 or (vote_speed_by >= 0 and vote_speed_by != p and vote_speed_q == q):
		speed_q = q
		vote_speed_by = -1
		return
	if vote_speed_by == p and vote_speed_q == q:
		vote_speed_by = -1
		return
	vote_speed_by = p
	vote_speed_q = q


func _answer(p: int, what: int, yes: bool) -> void:
	if what == 0 and vote_pause_by >= 0 and vote_pause_by != p:
		if yes:
			paused = vote_pause_want
		vote_pause_by = -1
	elif what == 1 and vote_speed_by >= 0 and vote_speed_by != p:
		if yes:
			speed_q = vote_speed_q
		vote_speed_by = -1


func _drop(who: int, to: int) -> void:
	var i := players.find(who)
	if i < 0:
		return
	active[i] = 0
	if to >= 0 and not is_active(to):
		to = -1
	for u in u_cmd.size():
		if u_cmd[u] == who:
			u_cmd[u] = to
			u_away[u] = who
	if vote_pause_by == who:
		vote_pause_by = -1
	if vote_speed_by == who:
		vote_speed_by = -1


func _admit(who: int, keep: int) -> void:
	var i := players.find(who)
	if i < 0 or active[i] != 0:
		return
	active[i] = 1
	drop_at.erase(who)
	for u in u_cmd.size():
		if u_away[u] == who:
			if keep == 0 or u_cmd[u] < 0:
				u_cmd[u] = who
			u_away[u] = -1
		elif u_cmd[u] < 0 and u_home[u] >= 0:
			u_cmd[u] = who


# ------------------------------------------------------------------ view ---

## Sim orders not applied yet (lockstep inputs not due + the sim's pending
## orders), in application order, for the order preview.
func pending_sim_orders() -> Array:
	var out: Array = []
	var qs := queue.duplicate()
	qs.sort_custom(_input_less)
	for o in qs:
		var typ := int(o.get("type", 0))
		if typ < BattleSim.ORDER_MOVE or typ > BattleSim.ORDER_REFILL:
			continue
		if typ == BattleSim.ORDER_WITHDRAW_ALL:
			for u in u_cmd.size():
				if u_cmd[u] == int(o["p"]) and sim.u_state[u] == BattleSim.U_READY:
					out.append({"tick": sim.tick, "type": BattleSim.ORDER_WITHDRAW, "unit": u})
			continue
		var u := int(o.get("unit", -1))
		if u < 0 or u >= u_cmd.size() or u_cmd[u] != int(o["p"]):
			continue
		var d: Dictionary = o.duplicate()
		d["tick"] = sim.tick
		out.append(d)
	for o in sim.pending_orders:
		if int(o.get("player", 0)) < 50:
			out.append(o)
	return out


# ------------------------------------------------------------------ hash ---

## 32-bit hash of the sim and the lockstep state every peer must agree on.
func state_hash() -> int:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_MD5)
	var head := PackedInt64Array([sim.state_hash(), frame, acc, speed_q, paused, vote_pause_by,
		vote_pause_want, vote_speed_by, vote_speed_q, players.size(), u_cmd.size()])
	ctx.update(head.to_byte_array())
	ctx.update(players.to_byte_array())
	ctx.update(active.to_byte_array())
	ctx.update(u_cmd.to_byte_array())
	ctx.update(u_away.to_byte_array())
	return ctx.finish().decode_u32(0)


# -------------------------------------------------------------- snapshot ---

## Everything (lockstep state, receipt state and the sim) as one blob.
func snapshot() -> PackedByteArray:
	var d := {"frame": frame, "acc": acc, "speed_q": speed_q, "paused": paused,
		"vote_pause_by": vote_pause_by, "vote_pause_want": vote_pause_want,
		"vote_speed_by": vote_speed_by, "vote_speed_q": vote_speed_q,
		"players": players, "active": active, "u_cmd": u_cmd, "u_away": u_away, "u_home": u_home,
		"queue": queue, "marks": marks, "last_n": last_n, "drop_at": drop_at, "last_s": last_s,
		"sim": sim.snapshot()}
	var raw := var_to_bytes(d)
	var out := PackedByteArray()
	out.resize(8)
	out.encode_u32(0, _MAGIC)
	out.encode_u32(4, raw.size())
	out.append_array(raw)  # the sim part is compressed already
	return out


## Load a snapshot() blob; the sim must already be set up with the same
## scenario and seed (setup()). Returns false on a bad blob.
func restore(blob: PackedByteArray) -> bool:
	if blob.size() < 8 or blob.decode_u32(0) != _MAGIC:
		return false
	var raw := blob.slice(8)
	if raw.size() != blob.decode_u32(4):
		return false
	var v = bytes_to_var(raw)
	if not (v is Dictionary):
		return false
	var d: Dictionary = v
	if not (d.get("sim") is PackedByteArray) or not (d.get("u_cmd") is PackedInt32Array):
		return false
	if (d["u_cmd"] as PackedInt32Array).size() != sim.n_units:
		return false
	if not sim.restore(d["sim"]):
		return false
	frame = int(d["frame"])
	acc = int(d["acc"])
	speed_q = int(d["speed_q"])
	paused = int(d["paused"])
	vote_pause_by = int(d["vote_pause_by"])
	vote_pause_want = int(d["vote_pause_want"])
	vote_speed_by = int(d["vote_speed_by"])
	vote_speed_q = int(d["vote_speed_q"])
	players = d["players"]
	active = d["active"]
	u_cmd = d["u_cmd"]
	u_away = d["u_away"]
	u_home = d["u_home"]
	queue = d["queue"]
	marks = d["marks"]
	last_n = d["last_n"]
	drop_at = d["drop_at"]
	last_s = int(d["last_s"])
	return true
