extends Node
## One live co-op battle on this device (milestone 5): the room connection
## (live_room.gd), the deterministic lockstep layer (sim/lockstep.gd) and
## everything between them. The battle view (game/battle.gd) drives it;
## tests drive it headless the same way.
##
## - Lobby: the room exists, the battle has not started; the host starts it
##   (at once when every human of the battle is in, after a short count, or
##   alone). The relay's "start" item fixes who takes part from frame 0.
## - Inputs: the view's orders and control requests are queued with
##   issue(); each frame one message {n, k, o} goes out with this player's
##   mark k = frame + delay (delay 0 while alone, else from the measured
##   round trip, 2-12 frames) and is applied locally at once.
## - Stream: every relayed item (start, in, drop) carries the room's
##   sequence number; items are applied strictly in that order (gaps are
##   filled by asking the relay to replay).
## - Frames run at 10 Hz of wall time while every taking-part player's
##   input is there; otherwise the sim waits ("Waiting for X" after 1 s). A
##   peer that is behind the others runs extra frames to catch up (the
##   view shows "Catching up").
## - Joining mid-battle, reconnecting with messages lost, a desync, or
##   coming back more than 10 s behind: ask for a snapshot (another player
##   sends one through the relay, or the relay's cache), restore it, replay
##   the stream after it, catch up. A player not taking part (joining, or
##   dropped) then says "ready" and the host admits them (a lockstep input),
##   which gives them their units back.
## - A player whose input is missing for 10 s while disconnected can be
##   continued without: Continue asks the relay to drop them (their units go
##   to this player, held for them).
## - Hashes go out every `hash_every` frames; a mismatch is logged and the
##   non-host resyncs from a host snapshot.
## - Telemetry: coop_net (every 10 s: round trip, delay, waits, messages),
##   coop_wait, coop_catchup, coop_snapshot, coop_desync, coop_drop.

signal changed                         ## roster / phase / votes / waiting changed (HUD refresh)
signal note(text: String, kind: String)  ## info, warn, error
signal failed(code: String, text: String)
signal resolved                        ## the battle's result is in on the server
signal setup_changed                   ## custom battle lobby: the setup (or its revision) changed

const CData := preload("res://campaign/cdata.gd")

const Lockstep := preload("res://sim/lockstep.gd")
const LiveRoom := preload("res://game/net/live_room.gd")
const BattleSim := preload("res://sim/battle_sim.gd")

const FRAME_SEC := 0.1
const CHUNK := 48000             ## base64 characters per snapshot chunk
const GRACE_SEC := 10.0          ## waiting this long for a disconnected player offers Continue
const RESYNC_BEHIND := 100       ## frames behind: a snapshot instead of stepping
const CACHE_SNAP_SEC := 30.0     ## the host leaves a snapshot with the relay this often
const AUTO_START_SEC := 3.0

var room: LiveRoom
var ls = null                    ## Lockstep once the battle runs here
var phase := "connecting"        ## connecting, lobby, sync, live, gone
var me := -1
var host := -1
var humans: Array = []           ## the battle's human factions
var roster: Array = []           ## [{f, on, in, dropped, joining, keep, silent_ms}]
var scenario: Dictionary = {}
var seed_value := 0
var home: Array = []
var scen_hash := ""
var battle_id := -1
var version := 0
var keep := false                ## joining: let the host keep command of my units
var hash_every := 10
var fixed_delay := -1            ## testing aid
var delay := 3
var auto_update := true          ## false: the battle view calls update() itself
var auto_start := true
var frame_sec := FRAME_SEC       ## testing aid: shorter frames run the battle faster
var grace_sec := GRACE_SEC

var my_n := 0
var sent_k := -1
var outbox: Array = []
var next_s := 1
var _pending := {}               ## s -> stream item not yet applied
var _gap_since := -1.0
var admitted_at := -1
var _ready_at := -1.0
var my_hashes := {}
var their_hashes := {}           ## frame -> {p: hash}
var wall_acc := 0.0
var last_steps := 0
var waiting: Array[int] = []
var wait_sec := 0.0
var takeover_offer := -1          ## player we may continue without (-1: none)
var _takeover_wait_until := 0.0
var final_result: Dictionary = {}
var final_frame := -1
var host_res := false            ## the host has sent the result
var result_in := false           ## the server has the result
var _their_res := {}
var catching_up := false
var catchup_total := 0
var _snap_rx := {}               ## id -> {cnt, parts}
var _snap_requested := -1.0
var _cache_t := CACHE_SNAP_SEC - 5.0  ## the first cached snapshot 5 s in
var _start_t := -1.0
var _tele: Node = null
var _net_t := 0.0
var _delay_t := 0.0
var _wait_start := -1.0
var _catch_t0 := 0
var _catch_from := 0
var _leaving := false
## Diagnostics.
var stats := {"waits": 0, "wait_ms_total": 0.0, "wait_ms_max": 0.0, "catchups": 0, "catchup_frames": 0,
	"catchup_ms": 0.0, "snap_sent": 0, "snap_bytes": 0, "snap_restored": 0, "restore_ms": 0.0, "resyncs": 0,
	"desyncs": 0, "hash_checks": 0, "replays": 0, "frames": 0, "drops": 0, "admits": 0}
var desync_log: Array = []

## Custom battles (docs/SERVER.md section 18): a room not tied to a
## campaign. The setup (an opaque JSON the clients build the scenario
## from, game/custom/custom_setup.gd) and its revision live on the relay;
## `builder` turns a setup into {scenario, seed, home}. Players are seats 0
## and 1 (Player 1, Player 2).
var custom := false
var custom_code := ""
var setup_data: Dictionary = {}
var setup_rev := 0
var builder := Callable()
var build_error := ""
var want_ready := false          ## custom lobby: this player pressed Ready for setup_rev
var names := {}                  ## player -> display name (else the campaign faction's)
var colors := {}                 ## player -> Color


## Unit -> player who commands it by default: a human's own units (the
## campaign faction of the unit, if that faction is a human in the battle),
## other friendly units (AI allies, garrisons of AI factions) -> the lowest
## human faction of the battle; enemy units -> -1.
static func home_of(built: Dictionary, p_humans: Array) -> Array:
	var out: Array = []
	var ctrl: Array = built["controller"]
	var ufac: Array = built["unit_faction"]
	var hs: Array = p_humans.duplicate()
	hs.sort()
	for u in ctrl.size():
		if int(ctrl[u]) < 0:
			out.append(-1)
		elif hs.has(int(ufac[u])):
			out.append(int(ufac[u]))
		else:
			out.append(int(hs[0]) if not hs.is_empty() else int(ctrl[u]))
	return out


## Hash of what both players must build identically.
static func scenario_hash(scn: Dictionary, p_seed: int, p_home: Array) -> String:
	return JSON.stringify([scn, p_seed, p_home]).md5_text().substr(0, 16)


func _ready() -> void:
	_tele = get_node_or_null("/root/Telemetry")


## built: CBattle.build() of the pending battle; create: open the room (the
## host) or join an existing one.
func setup(base: String, cid: String, token: String, p_me: int, built: Dictionary, p_humans: Array,
		p_version: int, create: bool, p_keep: bool = false) -> void:
	me = p_me
	humans = p_humans.duplicate()
	scenario = built["scenario"]
	seed_value = int(built["seed"])
	battle_id = int(built["battle"])
	version = p_version
	keep = p_keep
	home = home_of(built, humans)
	scen_hash = scenario_hash(scenario, seed_value, home)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--coop-delay="):
			fixed_delay = int(a.get_slice("=", 1))
		elif a.begins_with("--coop-hash-every="):
			hash_every = maxi(1, int(a.get_slice("=", 1)))
		elif a.begins_with("--coop-frame-ms="):
			frame_sec = maxf(0.002, int(a.get_slice("=", 1)) / 1000.0)
		elif a.begins_with("--coop-grace="):
			grace_sec = float(a.get_slice("=", 1))
	room = LiveRoom.new()
	add_child(room)
	room.message.connect(_on_message)
	room.failed.connect(func(code: String, text: String):
		phase = "gone"
		failed.emit(code, text)
		changed.emit())
	room.state_changed.connect(func(s: String):
		if s == "retrying" and phase in ["live", "lobby", "sync"]:
			_t("coop_disconnected", {"phase": phase})
		changed.emit())
	room.start(base, cid, token, {"b": battle_id, "v": version, "create": create, "scen": scen_hash, "keep": keep})


## A custom battle room: code from POST /api/custom (create) or
## /api/custom/join; token that call's seat token; me the seat (0 / 1).
func setup_custom(base: String, code: String, token: String, p_me: int, p_builder: Callable) -> void:
	custom = true
	custom_code = code
	me = p_me
	humans = [0, 1]
	builder = p_builder
	auto_start = false
	battle_id = 0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--coop-delay="):
			fixed_delay = int(a.get_slice("=", 1))
		elif a.begins_with("--coop-hash-every="):
			hash_every = maxi(1, int(a.get_slice("=", 1)))
		elif a.begins_with("--coop-frame-ms="):
			frame_sec = maxf(0.002, int(a.get_slice("=", 1)) / 1000.0)
		elif a.begins_with("--coop-grace="):
			grace_sec = float(a.get_slice("=", 1))
	room = LiveRoom.new()
	add_child(room)
	room.message.connect(_on_message)
	room.failed.connect(func(fcode: String, text: String):
		phase = "gone"
		failed.emit(fcode, text)
		changed.emit())
	room.state_changed.connect(func(s: String):
		if s == "retrying" and phase in ["live", "lobby", "sync"]:
			_t("coop_disconnected", {"phase": phase})
		changed.emit())
	room.start_url(base.replace("https://", "wss://").replace("http://", "ws://") + "/api/custom/%s/ws" % code,
		token, {"b": 0, "v": 0, "create": false, "scen": "", "keep": false})


## Custom battles: take a setup revision and build the battle from it.
func _take_setup(d: Dictionary, rev: int) -> void:
	if rev != setup_rev:
		want_ready = false  # the relay cleared every ready flag
	setup_data = d
	setup_rev = rev
	build_error = ""
	if builder.is_valid():
		var b: Dictionary = builder.call(d)
		if b.has("error"):
			build_error = str(b["error"])
		else:
			scenario = b["scenario"]
			seed_value = int(b["seed"])
			home = b["home"]
			scen_hash = scenario_hash(scenario, seed_value, home)
	setup_changed.emit()
	changed.emit()


## Custom lobby: send a new setup (compare-and-swap on the revision).
func send_setup(d: Dictionary) -> void:
	room.send({"t": "setup", "rev": setup_rev, "setup": d})


## Custom lobby: ready (or not) for the current setup revision.
func lobby_ready(on: bool) -> void:
	want_ready = on and build_error == ""
	room.send({"t": "lobby", "ready": on and build_error == "", "rev": setup_rev, "scen": scen_hash})


## Custom lobby: is player p ready at the current revision?
func lobby_is_ready(p: int) -> bool:
	return bool(player(p).get("ready", false))


func player_name(p: int) -> String:
	if names.has(p):
		return str(names[p])
	return CData.faction_name(p)


func player_color(p: int) -> Color:
	if colors.has(p):
		return colors[p]
	return CData.faction_color(p)


func _t(kind: String, d: Dictionary = {}) -> void:
	if _tele != null:
		d["battle"] = battle_id
		d["me"] = me
		d["frame"] = ls.frame if ls != null else -1
		_tele.event(kind, d)


func is_host() -> bool:
	return host == me


func player(f: int) -> Dictionary:
	for p in roster:
		if int(p["f"]) == f:
			return p
	return {}


func connected(f: int) -> bool:
	return bool(player(f).get("on", false))


# ------------------------------------------------------------ messages ---

func _on_message(m: Dictionary) -> void:
	match str(m.get("t", "")):
		"room":
			_on_room(m)
		"roster":
			host = int(m.get("host", host))
			roster = m.get("players", [])
			changed.emit()
		"start", "in", "drop":
			_on_item(m)
		"replay":
			stats["replays"] = int(stats["replays"]) + 1
			for it in m.get("items", []):
				if it is Dictionary:
					_on_item(it)
		"hash":
			_on_hash(int(m.get("p", -1)), int(m.get("fr", -1)), str(m.get("h", "")))
		"snapreq":
			_send_snapshot(int(m.get("to", -1)))
		"snap":
			_on_snap_chunk(m)
		"ready":
			_on_ready(int(m.get("p", -1)), bool(m.get("keep", false)))
		"res":
			if bool(m.get("up", false)):
				host_res = true
			elif final_frame >= 0 and int(m.get("fr", -1)) == final_frame:
				var mine := JSON.stringify(final_result).md5_text().substr(0, 8)
				if str(m.get("h", "")) != mine:
					stats["result_mismatch"] = 1
					_t("coop_result_mismatch", {"mine": mine, "theirs": str(m.get("h", "")), "peer": int(m.get("p", -1))})
			else:
				_their_res = m
		"resolved":
			result_in = true
			resolved.emit()
		"setup":
			if custom and m.get("setup") is Dictionary:
				_take_setup(m["setup"], int(m.get("rev", 0)))
		"error":
			var code := str(m.get("code", ""))
			if code == "replay_gone":
				_request_snapshot("replay gone")
			elif code == "no_snapshot":
				_snap_requested = -1.0
				note.emit("Nobody can send the battle right now; trying again.", "warn")
			elif code == "out_of_order" or code == "not_playing":
				# The relay and this device disagree about our messages:
				# take the relay's word (its counters, and a snapshot).
				_t("coop_refused", {"code": code, "message": str(m.get("message", ""))})
				if m.has("n"):
					my_n = int(m["n"])
					sent_k = int(m.get("k", sent_k))
					outbox.clear()
				if phase == "live":
					_request_snapshot(code)
			elif code in ["conflict", "not_ready", "scen_mismatch", "not_host", "started"] and custom:
				var why := {"conflict": "The setup changed meanwhile; here is the latest.",
					"not_ready": "Both players must be ready for this setup.",
					"scen_mismatch": "The two devices build this battle differently (different game versions?). Reload both.",
					"not_host": "Only the host starts the battle.", "started": "The battle has started."}
				note.emit(str(why.get(code, code)), "warn")
			else:
				note.emit("Server: %s" % str(m.get("message", code)), "warn")


func _on_room(m: Dictionary) -> void:
	host = int(m.get("host", -1))
	var their := str(m.get("scen", ""))
	if custom:
		their = ""
		if m.get("setup") is Dictionary and (int(m.get("rev", 0)) != setup_rev or setup_data.is_empty()):
			_take_setup(m["setup"], int(m.get("rev", 0)))
		if want_ready and not bool(m.get("started", false)):
			lobby_ready(true)  # (a reconnect clears it on the relay)
	if their != "" and their != scen_hash:
		phase = "gone"
		room.close()
		failed.emit("scenario", "This battle was set up differently on your ally's device (a different game version?). Reload the page on both devices.")
		return
	if not bool(m.get("started", false)):
		phase = "lobby"
		changed.emit()
		return
	var srv_n := int(m.get("n", 0))
	var srv_k := int(m.get("k", -1))
	if ls != null and phase == "live" and srv_n == my_n:
		# Reconnected with nothing lost: fetch what was missed.
		room.send({"t": "replay", "from": next_s})
		changed.emit()
		return
	# Joining a running battle, or our messages did not all arrive: start
	# from a snapshot and continue our numbering from the relay's.
	my_n = srv_n
	sent_k = maxi(sent_k, srv_k) if ls != null else srv_k
	outbox.clear()
	_request_snapshot("join" if ls == null else "reconnect")


func _on_item(it: Dictionary) -> void:
	var s := int(it.get("s", 0))
	if s < next_s and ls != null:
		return
	_pending[s] = it
	if str(it.get("t", "")) == "start" and ls == null:
		next_s = s
	if ls == null and phase != "lobby" and str(it.get("t", "")) != "start":
		return  # waiting for a snapshot; kept until then
	_drain()


func _drain() -> void:
	while _pending.has(next_s):
		var it: Dictionary = _pending[next_s]
		_pending.erase(next_s)
		_apply_item(it)
		next_s += 1
	if _pending.is_empty():
		_gap_since = -1.0
	elif _gap_since < 0.0:
		_gap_since = _now()
	if _pending.size() > 30000:
		_pending.clear()
		_request_snapshot("backlog")


func _apply_item(it: Dictionary) -> void:
	var t := str(it.get("t", ""))
	var s := int(it.get("s", 0))
	if t == "start":
		if ls != null:
			return
		var ps: Array = []
		for p in it.get("players", []):
			ps.append(int(p))
		ls = Lockstep.new()
		ls.setup(scenario, seed_value, home, ps, int(it.get("host", host)))
		ls.saw(s)
		phase = "live"
		if ps.has(me):
			my_n = 0
			sent_k = -1
		_t("coop_start", {"players": ps, "host": int(it.get("host", -1))})
		changed.emit()
		return
	if ls == null:
		return
	if t == "in":
		var r: String = ls.receive(it)
		if r == "gap":
			_request_snapshot("gap")
			return
		for o in it.get("o", []):
			if int(o.get("type", 0)) == Lockstep.C_ADMIT and int(o.get("who", -1)) == me:
				admitted_at = maxi(admitted_at, int(o.get("f", -1)))
				_ready_at = -1.0
	elif t == "drop":
		ls.receive_event(it)
		stats["drops"] = int(stats["drops"]) + 1
		var who := int(it.get("who", -1))
		_t("coop_drop", {"who": who, "to": int(it.get("to", -1)), "after": int(it.get("after", -1)), "why": str(it.get("why", ""))})
		if who == me:
			admitted_at = -1
	ls.saw(s)
	changed.emit()


# ------------------------------------------------------------ snapshots ---

func _request_snapshot(why: String) -> void:
	if _snap_requested > 0.0 and _now() - _snap_requested < 5.0:
		return
	_snap_requested = _now()
	if phase != "lobby":
		phase = "sync"
	stats["resyncs"] = int(stats["resyncs"]) + 1
	_t("coop_resync", {"why": why})
	room.send({"t": "snapreq"})
	changed.emit()


func _send_snapshot(to: int) -> void:
	if ls == null or phase != "live":
		return
	var t0 := Time.get_ticks_usec()
	var blob: PackedByteArray = ls.snapshot()
	var b64 := Marshalls.raw_to_base64(blob)
	var cnt := maxi(1, (b64.length() + CHUNK - 1) / CHUNK)
	var sid := "%d-%d-%d" % [me, ls.frame, Time.get_ticks_msec() % 100000]
	for i in cnt:
		room.send({"t": "snap", "id": sid, "to": to, "i": i, "cnt": cnt, "fr": ls.frame, "ls": ls.last_s,
			"d": b64.substr(i * CHUNK, CHUNK)})
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	stats["snap_sent"] = int(stats["snap_sent"]) + 1
	stats["snap_bytes"] = blob.size()
	if to >= 0:
		_t("coop_snapshot", {"dir": "sent", "to": to, "bytes": blob.size(), "chunks": cnt, "ms": ms, "soldiers": ls.sim.n})


func _on_snap_chunk(m: Dictionary) -> void:
	if phase != "sync" and not (phase == "connecting"):
		return
	var sid := str(m.get("id", ""))
	var cnt := int(m.get("cnt", 1))
	var i := int(m.get("i", 0))
	if not _snap_rx.has(sid):
		_snap_rx = {sid: {"cnt": cnt, "parts": {}}}
	var e: Dictionary = _snap_rx[sid]
	e["parts"][i] = str(m.get("d", ""))
	if (e["parts"] as Dictionary).size() < cnt:
		return
	var b64 := ""
	for k in cnt:
		b64 += str(e["parts"].get(k, ""))
	_snap_rx.clear()
	var blob := Marshalls.base64_to_raw(b64)
	var t0 := Time.get_ticks_usec()
	var nls := Lockstep.new()
	nls.setup(scenario, seed_value, home, [], -1)
	if not nls.restore(blob):
		_t("coop_snapshot", {"dir": "bad", "bytes": blob.size()})
		note.emit("The battle could not be loaded from your ally's device.", "error")
		_snap_requested = -1.0
		return
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	var behind: int = ls.frame - nls.frame if ls != null else 0
	ls = nls
	next_s = ls.last_s + 1
	for s in _pending.keys():
		if int(s) < next_s:
			_pending.erase(s)
	phase = "live"
	_snap_requested = -1.0
	stats["snap_restored"] = int(stats["snap_restored"]) + 1
	stats["restore_ms"] = ms
	stats["snap_rx_bytes"] = blob.size()
	my_hashes.clear()
	for fr in their_hashes.keys():
		if int(fr) <= ls.frame:
			their_hashes.erase(fr)
	_t("coop_snapshot", {"dir": "restored", "bytes": blob.size(), "ms": ms, "snap_frame": ls.frame, "was_at": behind,
		"soldiers": ls.sim.n})
	# What the relay sent after the snapshot: from our buffer, the rest by replay.
	_drain()
	room.send({"t": "replay", "from": next_s})
	_start_catchup()
	if not ls.is_active(me):
		_say_ready()
	changed.emit()


func _say_ready() -> void:
	_ready_at = _now()
	room.send({"t": "ready"})


func _start_catchup() -> void:
	catching_up = true
	_catch_t0 = Time.get_ticks_msec()
	_catch_from = ls.frame
	catchup_total = maxi(1, ls.max_mark(me) - ls.frame)


func _on_ready(p: int, p_keep: bool) -> void:
	if ls == null or phase != "live":
		return
	if p == me and ls.active_count() == 0:
		issue({"type": Lockstep.C_ADMIT, "who": me, "keep": 0})
		return
	if not is_host() or p == me:
		return
	if ls.is_active(p) and not ls.drop_at.has(p):
		return
	stats["admits"] = int(stats["admits"]) + 1
	issue({"type": Lockstep.C_ADMIT, "who": p, "keep": 1 if p_keep else 0, "min_f": int(ls.drop_at.get(p, 0))})
	_t("coop_admit", {"who": p, "keep": p_keep})


# --------------------------------------------------------------- hashes ---

func _on_hash(p: int, fr: int, h: String) -> void:
	if not their_hashes.has(fr):
		their_hashes[fr] = {}
	their_hashes[fr][p] = h
	_compare(fr)


func _compare(fr: int) -> void:
	if not my_hashes.has(fr) or not their_hashes.has(fr):
		return
	var mine: String = my_hashes[fr]
	for p in their_hashes[fr]:
		stats["hash_checks"] = int(stats["hash_checks"]) + 1
		var theirs: String = their_hashes[fr][p]
		if theirs != mine:
			stats["desyncs"] = int(stats["desyncs"]) + 1
			desync_log.append({"frame": fr, "mine": mine, "theirs": theirs, "peer": int(p)})
			_t("coop_desync", {"at": fr, "mine": mine, "theirs": theirs, "peer": int(p), "host": host})
			note.emit("Out of step with your ally at %d:%02d; resyncing." % [fr / 600, (fr / 10) % 60], "warn")
			if not is_host():
				_request_snapshot("desync")
	their_hashes.erase(fr)


# -------------------------------------------------------------- inputs ---

## Queue an input (a sim order without "tick", or a Lockstep control
## input). Sent with the next frame's message.
func issue(o: Dictionary) -> void:
	var d := {}
	for k in o:
		if k == "tick" or k == "player" or k == "seq":
			continue
		d[k] = int(o[k])
	outbox.append(d)


func can_issue() -> bool:
	return ls != null and phase == "live" and (ls.is_active(me) or admitted_at >= 0)


func can_order(u: int) -> bool:
	return ls != null and ls.commander(u) == me


func _flush() -> void:
	if ls == null or phase != "live":
		return
	var self_admit := false
	for o in outbox:
		if int(o.get("type", 0)) == Lockstep.C_ADMIT and int(o.get("who", -1)) == me:
			self_admit = true
	if not ls.is_active(me) and admitted_at < 0 and not self_admit:
		outbox.clear()
		return
	var alone: bool = ls.active_count() <= 1 and ls.is_active(me)
	var d := 0 if alone else (fixed_delay if fixed_delay >= 0 else delay)
	var target: int = ls.frame + d
	target = maxi(target, ls.max_mark(me))
	if admitted_at >= 0:
		target = maxi(target, admitted_at)
	for o in outbox:
		if o.has("min_f"):
			target = maxi(target, int(o["min_f"]))
	var k := maxi(target, sent_k)
	if not outbox.is_empty():
		k = maxi(k, sent_k + 1)
	if k <= sent_k:
		return
	var os: Array = []
	for o in outbox:
		var o2: Dictionary = o.duplicate()
		o2.erase("min_f")
		o2["f"] = k
		os.append(o2)
	outbox.clear()
	my_n += 1
	sent_k = k
	var msg := {"p": me, "n": my_n, "k": k, "o": os}
	ls.receive(msg)
	if not room.send({"t": "in", "n": my_n, "k": k, "o": os}):
		# Not connected: the relay never got it. The reconnect sees our
		# count ahead of the relay's and resyncs.
		pass


# ---------------------------------------------------------------- frames ---

func _process(delta: float) -> void:
	if auto_update:
		update(delta)


## Run the frames due (and network bookkeeping). Returns sim ticks stepped.
func update(delta: float) -> int:
	last_steps = 0
	_house(delta)
	if ls == null or phase != "live":
		return 0
	_flush()
	wall_acc += delta
	var behind: int = ls.max_mark(me) - (fixed_delay if fixed_delay >= 0 else delay) - ls.frame
	if behind > RESYNC_BEHIND and not is_host() and not catching_up:
		# Far behind (the page was in the background): a snapshot is faster.
		_request_snapshot("behind %d" % behind)
		return 0
	if behind > 3 and not catching_up:
		_start_catchup()
	var want := int(wall_acc / frame_sec)
	var t0 := Time.get_ticks_usec()
	var frames := 0
	var budget_us := 30000 if catching_up else 60000
	while ls.can_advance() and (frames < want or (catching_up and ls.frame < ls.max_mark(me) - 1)):
		last_steps += ls.advance()
		frames += 1
		_after_frame()
		if frames % 4 == 0:
			_flush()
		if Time.get_ticks_usec() - t0 > budget_us and frames >= mini(want, 1):
			break
	stats["frames"] = int(stats["frames"]) + frames
	wall_acc = maxf(wall_acc - frames * frame_sec, 0.0)
	if catching_up and ls.frame >= ls.max_mark(me) - (fixed_delay if fixed_delay >= 0 else delay) - 1:
		catching_up = false
		var cms := Time.get_ticks_msec() - _catch_t0
		stats["catchups"] = int(stats["catchups"]) + 1
		stats["catchup_frames"] = int(stats["catchup_frames"]) + ls.frame - _catch_from
		stats["catchup_ms"] = float(stats["catchup_ms"]) + cms
		_t("coop_catchup", {"frames": ls.frame - _catch_from, "ms": cms})
		changed.emit()
	# Waiting for someone's input?
	var w: Array[int] = []
	if want > frames:
		w = ls.waiting_for()
	if not w.is_empty():
		wall_acc = minf(wall_acc, 0.3)
		if _wait_start < 0.0:
			_wait_start = _now()
		wait_sec = _now() - _wait_start
		if w != waiting:
			waiting = w
			changed.emit()
		_check_takeover(w)
	elif _wait_start >= 0.0:
		var ms := (_now() - _wait_start) * 1000.0
		_wait_start = -1.0
		wait_sec = 0.0
		stats["waits"] = int(stats["waits"]) + 1
		stats["wait_ms_total"] = float(stats["wait_ms_total"]) + ms
		stats["wait_ms_max"] = maxf(float(stats["wait_ms_max"]), ms)
		if ms >= 500.0:
			_t("coop_wait", {"ms": int(ms), "for": waiting})
		waiting = []
		takeover_offer = -1
		changed.emit()
	_flush()
	return last_steps


func _after_frame() -> void:
	if ls.frame % hash_every == 0:
		var h := "%08x" % ls.state_hash()
		my_hashes[ls.frame] = h
		room.send({"t": "hash", "fr": ls.frame, "h": h})
		_compare(ls.frame)
		if my_hashes.size() > 400:
			for fr in my_hashes.keys():
				if int(fr) < ls.frame - 3000:
					my_hashes.erase(fr)
		if their_hashes.size() > 400:
			for fr in their_hashes.keys():
				if int(fr) < ls.frame - 3000:
					their_hashes.erase(fr)
	if ls.sim.ended != 0 and final_frame < 0:
		final_frame = ls.frame
		final_result = ls.sim.result()
		var h := JSON.stringify(final_result).md5_text().substr(0, 8)
		room.send({"t": "res", "fr": final_frame, "h": h})
		_t("coop_result", {"hash": h, "tick": ls.sim.tick})
		if not _their_res.is_empty():
			var m := _their_res
			_their_res = {}
			if int(m.get("fr", -1)) == final_frame and str(m.get("h", "")) != h:
				stats["result_mismatch"] = 1
				_t("coop_result_mismatch", {"mine": h, "theirs": str(m.get("h", "")), "peer": int(m.get("p", -1))})


func _check_takeover(w: Array[int]) -> void:
	if wait_sec < grace_sec or _now() < _takeover_wait_until:
		return
	for p in w:
		var info := player(p)
		if not bool(info.get("on", false)) or int(info.get("silent_ms", 0)) > 8000 or wait_sec > 2.0 * grace_sec:
			if takeover_offer != p:
				takeover_offer = p
				changed.emit()
			return


## The player chose Continue: the relay drops `who`; their units come here.
func continue_without(who: int) -> void:
	room.send({"t": "continue", "who": who})
	takeover_offer = -1
	_t("coop_continue", {"who": who})
	changed.emit()


## The player chose to wait longer before being asked again.
func wait_longer() -> void:
	takeover_offer = -1
	_takeover_wait_until = _now() + grace_sec
	changed.emit()


func _house(delta: float) -> void:
	# Lobby: the host starts when every human is in (after a short count).
	if phase == "lobby" and is_host() and auto_start:
		var all_in := true
		for h in humans:
			if not connected(int(h)):
				all_in = false
		if all_in and humans.size() > 1:
			if _start_t < 0.0:
				_start_t = _now()
				changed.emit()
			elif _now() - _start_t >= AUTO_START_SEC:
				start_battle()
		elif _start_t >= 0.0:
			_start_t = -1.0
			changed.emit()
	if ls == null:
		return
	if phase == "live":
		if _gap_since > 0.0 and _now() - _gap_since > 2.0:
			_gap_since = _now()
			room.send({"t": "replay", "from": next_s})
		if not ls.is_active(me) and admitted_at < 0 and not catching_up and room.is_open() and not _leaving \
				and (_ready_at < 0.0 or _now() - _ready_at > 5.0) and ls.waiting_for().is_empty():
			# Not taking part (joined mid-battle, or dropped while away and
			# back by replay): ask the host to admit us (again after 5 s).
			_say_ready()
		if is_host():
			_cache_t += delta
			if _cache_t >= CACHE_SNAP_SEC:
				_cache_t = 0.0
				_send_snapshot(-1)
	elif phase == "sync" and _snap_requested > 0.0 and _now() - _snap_requested > 8.0:
		_snap_requested = -1.0
		_request_snapshot("retry")
	_delay_t -= delta
	if _delay_t <= 0.0:
		_delay_t = 2.0
		if room.srtt_ms >= 0.0:
			delay = clampi(int(ceil((room.srtt_ms + 4.0 * room.rttvar_ms + 50.0) / 100.0)), 2, 12)
	_net_t += delta
	if _net_t >= 10.0:
		_net_t = 0.0
		_t("coop_net", {"rtt_ms": room.srtt_ms, "rttvar_ms": room.rttvar_ms, "delay": delay, "waits": stats["waits"],
			"wait_ms_total": stats["wait_ms_total"], "wait_ms_max": stats["wait_ms_max"], "sent": room.sent,
			"received": room.received, "reconnects": room.reconnects, "desyncs": stats["desyncs"],
			"frame": ls.frame, "tick": ls.sim.tick, "active": ls.active_players()})


## Seconds until the automatic start (-1: not counting).
func start_in() -> float:
	if _start_t < 0.0:
		return -1.0
	return maxf(AUTO_START_SEC - (_now() - _start_t), 0.0)


func start_battle() -> void:
	if phase == "lobby" and is_host():
		room.send({"t": "start"})
		_start_t = -1.0


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


# ----------------------------------------------------------- the view ---

## Pause / resume request (a vote while two players take part).
func request_pause() -> void:
	if ls == null:
		return
	issue({"type": Lockstep.C_PAUSE, "want": 1 - ls.paused})


func request_speed(q: int) -> void:
	issue({"type": Lockstep.C_SPEED, "q": q})


func answer(what: int, yes: bool) -> void:
	issue({"type": Lockstep.C_ANSWER, "what": what, "yes": 1 if yes else 0})


func gift(units: Array, to: int) -> void:
	for u in units:
		if can_order(int(u)):
			issue({"type": Lockstep.C_GIFT, "unit": int(u), "to": to})


## The other human players of the battle.
func others() -> Array:
	var out: Array = []
	for h in humans:
		if int(h) != me:
			out.append(int(h))
	return out


## Upload the result from here? The host does; another player only if the
## host is gone without having sent it.
func should_upload() -> bool:
	return is_host() and not result_in and not host_res


## Tell the others this device uploads the result (so a player who becomes
## host after we leave does not upload it again).
func announce_upload() -> void:
	room.send({"t": "res", "up": true, "fr": final_frame})


## Leave the room (the others continue; our units go to them).
func leave() -> void:
	if _leaving:
		return
	_leaving = true
	_t("coop_leave", {"stats": stats})
	if room != null:
		room.send({"t": "leave"})
		var r := room
		get_tree().create_timer(0.5).timeout.connect(func(): if is_instance_valid(r): r.close())
	phase = "gone"
