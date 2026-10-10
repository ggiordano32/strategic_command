extends Node
## One seat in an online campaign. Keeps the local copy of the shared state
## in step with the server, and does everything the server will not: it runs
## the rules (campaign/cturn.gd) to resolve turns and apply battle results,
## then uploads the new state with the version it started from
## (compare-and-swap: one upload per version wins, the rest refetch).
##
## - open(): local cache first (plays offline), then sync, then a long-poll
##   loop on the campaign's change counter (changes appear without a
##   refresh; falls back to retrying with backoff when the server is gone).
## - Plans in progress go to the seat's session blob on the server
##   (debounced), so a turn started on the phone can be finished on a desktop.
## - submit(): replaces this seat's submission. When every seat is in, the
##   last submitter resolves at once; any other open client resolves after
##   `resolve_grace` seconds if nobody has (page closed mid-way).
## - Battle results go through a local outbox (saved before the upload) and
##   are retried until the server confirms; on a version conflict the result
##   is re-applied on the newer state, and dropped only if that battle is no
##   longer pending.
## - Determinism check: when a version made by another device arrives, the
##   previous version and the inputs are fetched and the step is re-run
##   here; a different hash is reported (telemetry, server, the player).
##
## Local cache: user://online/<id>.json {state, version, hash, session,
## outbox, mine, verified}.

signal changed(what: String)             ## "state", "summary", "session"
signal note(text: String, kind: String)  ## a message for the player (kind: info, warn, error)
signal desync(version: int, local_hash: String, server_hash: String)

const AudioFx := preload("res://game/audio.gd")
const CState := preload("res://campaign/cstate.gd")
const CTurn := preload("res://campaign/cturn.gd")
const CRules := preload("res://campaign/crules.gd")

const PLAN_DEBOUNCE := 1.5
const HEARTBEAT := 30.0
const POLL_TIMEOUT := 25

var api: Node                 ## game/net/api.gd
var id := ""
var f := -1
var token := ""
var rules := ""
var build := ""
var cache_dir := "user://online/"

var st: Dictionary = {}
var version := 0
var state_hash := ""
var summary: Dictionary = {}
var seq := 0
var session: Dictionary = {"turn": -1, "orders": [], "seen": -1, "saved_at": 0}
var outbox: Array = []        ## [{bid, outcome, at}]
var mine := {}                ## versions this device made: str(version) -> 1
var verified := {}            ## str(version) -> 1 ok / 0 mismatch
var verify_enabled := true
var resolve_grace := 4.0
var refused := ""             ## why this campaign cannot be played here ("" = fine)
var offline := false
var last_resolve := {}        ## {base, computed, result: won / already / lost / ...}
var resolve_barrier := Callable()  ## testing aid: awaited between computing and uploading

var _closed := false
var _syncing := false
var _sync_again := false
var _plan_dirty := false
var _plan_timer := 0.0
var _leases := {}             ## bid -> true while heartbeating
var _resolving := false
var _flushing := false
var _outbox_retry := 0.0      ## seconds until the next outbox attempt (0 = none)
var _outbox_backoff := 3.0
var _auto_resolve_for := -1
var _tele: Node = null


func setup(p_api: Node, p_id: String, p_f: int, p_token: String, p_rules: String, p_build: String) -> void:
	api = p_api
	id = p_id
	f = p_f
	token = p_token
	rules = p_rules
	build = p_build


func _ready() -> void:
	_tele = get_node_or_null("/root/Telemetry")


func _t(kind: String, d: Dictionary = {}) -> void:
	if _tele != null:
		d["campaign"] = id
		_tele.event(kind, d)


func _path(p: String) -> String:
	return "/api/c/%s%s" % [id, p]


func _api(method: String, p: String, body = null, opts: Dictionary = {}) -> Dictionary:
	var r: Dictionary = await api.call_api(method, _path(p), body, token, opts)
	if not r["ok"]:
		if r["network"]:
			_set_offline(true)
		else:
			_set_offline(false)
			if int(r["status"]) == 401:
				refused = "This device's key for the campaign is no longer valid. Join again with a device code."
		if int(r["status"]) >= 500 or (not r["network"] and int(r["status"]) != 409):
			_t("online_error", {"path": p.get_slice("?", 0), "status": int(r["status"]), "error": str(r["error"])})
	else:
		_set_offline(false)
	return r


func _set_offline(v: bool) -> void:
	if v != offline:
		offline = v
		_t("online_reachability", {"online": not v})
		changed.emit("summary")


# ------------------------------------------------------------- lifecycle ---

## Open: local cache, then the server; starts watching for changes.
func open() -> void:
	_load_cache()
	if not st.is_empty():
		changed.emit("state")
	await sync(true)
	_watch_loop()
	if not outbox.is_empty():
		_flush_outbox()


func close() -> void:
	if _closed:
		return
	if _plan_dirty:
		_push_session()
	for bid in _leases.keys():
		release(int(bid))
	_closed = true


func _process(delta: float) -> void:
	if _plan_dirty:
		_plan_timer -= delta
		if _plan_timer <= 0.0:
			_plan_dirty = false
			_push_session()
	if _outbox_retry > 0.0:
		_outbox_retry -= delta
		if _outbox_retry <= 0.0:
			_outbox_retry = 0.0
			_flush_outbox()


# ------------------------------------------------------------------ sync ---

## Bring the local copy up to date (summary; state if the version moved).
func sync(fetch_session: bool = false) -> bool:
	if _syncing:
		_sync_again = true
		while _syncing:
			await get_tree().process_frame
		return not offline
	_syncing = true
	var ok := true
	while true:
		_sync_again = false
		ok = await _sync_once(fetch_session)
		fetch_session = false
		if not _sync_again:
			break
	_syncing = false
	return ok


func _sync_once(fetch_session: bool) -> bool:
	var r := await _api("GET", "")
	if not r["ok"]:
		changed.emit("summary")
		return false
	summary = CState.normalise(r["data"])  # JSON numbers -> ints (Array.has(int) needs ints)
	seq = int(summary.get("seq", 0))
	# Online states keep the format their campaign was made with (the server
	# pins it); this build reads every format from MIN_VERSION up (rules
	# fall back to defaults for fields an older format lacks).
	if int(summary.get("format_version", 0)) > CState.VERSION or int(summary.get("format_version", 0)) < CState.MIN_VERSION:
		refused = "This campaign uses save format %d; this game build reads format %d. Update the game (reload the page) before playing it." % [
			int(summary.get("format_version", 0)), CState.VERSION]
		changed.emit("summary")
		return false
	if int(summary["version"]) != version or st.is_empty():
		var r2 := await _api("GET", "/state")
		if not r2["ok"]:
			return false
		var d: Dictionary = r2["data"]
		var nst: Dictionary = CState.normalise(d.get("state", {}))
		var h := CState.hash_text(nst)
		if h != str(d.get("hash", "")):
			note.emit("The downloaded campaign did not match its checksum; trying again later.", "error")
			_t("online_error", {"what": "download hash", "got": h, "want": str(d.get("hash", ""))})
			return false
		var prev := version
		if fetch_session:
			# Before the first look: which turn summary this seat has seen
			# and the plan in progress may come from another device.
			await _fetch_session(false)
			fetch_session = false
		st = nst
		version = int(d["version"])
		state_hash = h
		_save_cache()
		changed.emit("state")
		if verify_enabled and prev > 0 and not mine.has(str(version)) and str(d.get("kind", "")) in ["turn", "battle"]:
			verify(version)
	if fetch_session:
		await _fetch_session()
	changed.emit("summary")
	_maybe_auto_resolve()
	return true


func _watch_loop() -> void:
	var backoff := 2.0
	while not _closed:
		var r: Dictionary = await api.call_api("GET", _path("/wait?since=%d&timeout=%d" % [seq, POLL_TIMEOUT]), null, token,
			{"timeout": POLL_TIMEOUT + 15, "retries": 0})
		if _closed:
			break
		if r["ok"]:
			if offline:
				_set_offline(false)
			backoff = 2.0
			if int(r["data"].get("seq", 0)) != seq:
				await sync()
				if not outbox.is_empty() and not _flushing:
					_flush_outbox()
			continue
		if int(r["status"]) == 401:
			refused = "This device's key for the campaign is no longer valid."
			changed.emit("summary")
			break
		_set_offline(r["network"])
		await get_tree().create_timer(backoff * randf_range(0.8, 1.2)).timeout
		backoff = minf(backoff * 2.0, 60.0)
		if not _closed:
			await sync()


# -------------------------------------------------------------- session ---

## The plan being made for the current turn (from this or another device).
func plan_orders() -> Array:
	if int(session.get("turn", -1)) == int(st.get("turn", -2)) and session.get("orders") is Array:
		return (session["orders"] as Array).duplicate(true)
	return []


func set_plan(orders: Array) -> void:
	session["turn"] = int(st.get("turn", 0))
	session["orders"] = orders.duplicate(true)
	_touch_session()


func seen_turn() -> int:
	return int(session.get("seen", -1))


func set_seen(turn: int) -> void:
	if int(session.get("seen", -1)) != turn:
		session["seen"] = turn
		_touch_session()


func _touch_session() -> void:
	session["saved_at"] = int(Time.get_unix_time_from_system() * 1000.0)
	_plan_dirty = true
	_plan_timer = PLAN_DEBOUNCE
	_save_cache()


## Send the session now (also called on close).
func flush_session() -> void:
	if _plan_dirty:
		_plan_dirty = false
		await _push_session()


func _push_session() -> void:
	var r := await _api("POST", "/session", {"data": session}, {"retries": 2})
	if not r["ok"] and r["network"]:
		_plan_dirty = true
		_plan_timer = 10.0


func _fetch_session(emit: bool = true) -> void:
	var r := await _api("GET", "/session")
	if not r["ok"] or not (r["data"].get("data") is Dictionary):
		return
	var remote: Dictionary = CState.normalise(r["data"]["data"])
	if int(remote.get("saved_at", 0)) > int(session.get("saved_at", 0)):
		session = remote
		if not session.has("orders"):
			session["orders"] = []
		_save_cache()
		if emit:
			changed.emit("session")


# ---------------------------------------------------------------- turns ---

func i_submitted() -> bool:
	return (summary.get("submitted", []) as Array).has(f)


func submit(orders: Array) -> Dictionary:
	var sub := CTurn.submission(st, f, orders)
	var r := await _api("POST", "/submit", {"base_version": version, "submission": sub}, {"retries": 2})
	if r["ok"]:
		session["submitted"] = {"turn": int(st["turn"]), "orders": orders.duplicate(true)}
		_touch_session()
		_t("online_submit", {"turn": int(st["turn"]), "orders": orders.size(), "all_in": r["data"].get("all_in", false)})
		await sync()
		if bool(r["data"].get("all_in", false)):
			await resolve_now(false)
	elif int(r["status"]) == 409:
		await sync()
	return r


func unsubmit() -> Dictionary:
	var r := await _api("POST", "/unsubmit", {"turn": int(st.get("turn", 0))})
	await sync()
	return r


func ping(bid: int = -1) -> Dictionary:
	var body := {} if bid < 0 else {"battle_id": bid}
	return await _api("POST", "/ping", body)


func _maybe_auto_resolve() -> void:
	if str(summary.get("phase", "")) != "plan" or not bool(summary.get("all_in", false)) or _resolving:
		return
	if _auto_resolve_for == version:
		return
	_auto_resolve_for = version
	var v := version
	await get_tree().create_timer(resolve_grace).timeout
	if _closed or version != v:
		return
	await sync()
	if version == v and bool(summary.get("all_in", false)) and str(summary.get("phase", "")) == "plan":
		await resolve_now(false)


## Resolve the turn here and upload it. forced: the deadline has passed and
## the missing seats submit nothing. Returns "ok", "already", "lost" (another
## client's upload won), "not_ready", "busy", "network" or an error code.
func resolve_now(forced: bool = false) -> String:
	if _resolving:
		return "busy"
	_resolving = true
	var res := await _resolve(forced)
	_resolving = false
	return res


func _resolve(forced: bool) -> String:
	var r := await _api("GET", "/resolve-input")
	if not r["ok"]:
		return "network" if r["network"] else str(r["error"])
	var d: Dictionary = r["data"]
	if int(d["base_version"]) != version:
		await sync()
		if int(d["base_version"]) != version:
			return "stale"
	if not bool(d.get("can_resolve", false)) or (not bool(d.get("all_in", false)) and not forced):
		return "not_ready"
	var subs: Array = CState.normalise(d.get("submissions", []))
	var t0 := Time.get_ticks_msec()
	var base := st
	var nst := CTurn.resolve_turn(base, subs)
	var text := CState.to_json(nst)
	var h := CState.hash_text(nst)
	var ms := Time.get_ticks_msec() - t0
	if resolve_barrier.is_valid():
		await resolve_barrier.call()
	var body := {"base_version": int(d["base_version"]), "kind": "turn", "hash": h, "state_gz": gz64(text),
		"subs_rev": int(d["subs_rev"]), "forced": forced and not bool(d.get("all_in", false)), "rules": rules, "build": build}
	var up := await _api("POST", "/state", body, {"retries": 3})
	last_resolve = {"base": int(d["base_version"]), "computed": h, "ms": ms, "turn": int(base["turn"])}
	if up["ok"]:
		var already := bool(up["data"].get("already", false))
		last_resolve["result"] = "already" if already else "won"
		_adopt(nst, int(up["data"]["version"]), h)
		_t("online_resolved", {"turn": int(base["turn"]), "ms": ms, "hash": h, "forced": body["forced"], "already": already,
			"battles": (nst["battles"] as Array).size()})
		return "already" if already else "ok"
	if int(up["status"]) == 409:
		last_resolve["result"] = "lost"
		await sync()
		# Free determinism check: the winner resolved the same inputs.
		if version == int(d["base_version"]) + 1 and str(summary.get("last", {}).get("kind", "")) == "turn":
			var same := state_hash == h
			verified[str(version)] = 1 if same else 0
			last_resolve["server"] = state_hash
			if not same:
				_report_desync(version, h, state_hash)
		return "lost"
	last_resolve["result"] = str(up["error"])
	return "network" if up["network"] else str(up["error"])


func _adopt(nst: Dictionary, v: int, h: String) -> void:
	# The notification sound: a new turn (or a battle waiting) arrived.
	if not st.is_empty() and int(nst.get("turn", 0)) != int(st.get("turn", 0)):
		AudioFx.play("battle_pending" if not (nst.get("battles", []) as Array).is_empty() else "turn_resolved", 0.9, 0.0, "horn")
	st = nst
	version = v
	state_hash = h
	mine[str(v)] = 1
	_save_cache()
	changed.emit("state")
	sync()


static func gz64(text: String) -> String:
	return Marshalls.raw_to_base64(text.to_utf8_buffer().compress(FileAccess.COMPRESSION_GZIP))


# -------------------------------------------------------------- battles ---

## Battle entry from the summary ({} if not pending).
func battle_info(bid: int) -> Dictionary:
	for b in summary.get("battles", []):
		if int(b["id"]) == bid:
			return b
	return {}


## The state at version v ({} if it cannot be fetched): a live battle is
## built from the version its room was opened at.
func state_at(v: int) -> Dictionary:
	if v == version and not st.is_empty():
		return st
	var r := await _api("GET", "/state?version=%d" % v)
	if not r["ok"]:
		return {}
	var d: Dictionary = r["data"]
	var nst: Dictionary = CState.normalise(d.get("state", {}))
	if CState.hash_text(nst) != str(d.get("hash", "")):
		return {}
	return nst


## Live rooms need the server's API 2 (milestone 5).
func live_ok() -> bool:
	var net := get_node_or_null("/root/Net")
	return net != null and int(net.info.get("api", 0)) >= 2


func claim(bid: int, mode: String) -> Dictionary:
	var r := await _api("POST", "/battles/%d/claim" % bid, {"mode": mode})
	if r["ok"]:
		if not _leases.has(bid):
			_leases[bid] = true
			_heartbeat(bid)
		sync()
	return r


func _heartbeat(bid: int) -> void:
	while _leases.has(bid) and not _closed:
		await get_tree().create_timer(HEARTBEAT).timeout
		if not _leases.has(bid) or _closed:
			break
		var r := await _api("POST", "/battles/%d/heartbeat" % bid)
		if not r["ok"] and int(r["status"]) == 409:
			_leases.erase(bid)
			if str(r["error"]) == "lost_lease":
				note.emit("Another device took over this battle while you were away.", "warn")


func release(bid: int) -> void:
	_leases.erase(bid)
	await _api("POST", "/battles/%d/release" % bid)


func choose(bid: int, choice: String) -> Dictionary:
	var r := await _api("POST", "/battles/%d/choice" % bid, {"choice": choice})
	await sync()
	return r


## Upload a battle outcome (from the sim, auto-resolve or a forfeit). It is
## saved locally first and retried until the server has it.
func upload_battle(bid: int, outcome: Dictionary) -> String:
	var o: Dictionary = CState.normalise(JSON.parse_string(JSON.stringify(outcome)))
	outbox.append({"bid": bid, "outcome": o, "at": int(Time.get_unix_time_from_system())})
	_save_cache()
	return await _flush_outbox()


func _flush_outbox() -> String:
	if _flushing:
		return "busy"
	_flushing = true
	var result := "ok"
	while not outbox.is_empty() and not _closed:
		var item: Dictionary = outbox[0]
		var bid := int(item["bid"])
		if CState.battle(st, bid).is_empty():
			# Not pending in our copy: make sure the copy is current first.
			if not await sync():
				result = "network"
				_outbox_retry = _outbox_backoff
				break
			if CState.battle(st, bid).is_empty():
				# Was it our own earlier attempt whose answer got lost? The
				# server answers "already" to a replay of the winning upload.
				var mine_already := false
				if item.has("base"):
					var rr := await _api("POST", "/state", {"base_version": int(item["base"]), "kind": "battle",
						"battle_id": bid, "outcome": item["outcome"], "hash": str(item["hash"]), "state_gz": str(item["gz"]),
						"rules": rules, "build": build})
					mine_already = rr["ok"] and bool(rr["data"].get("already", false))
					if mine_already:
						mine[str(int(rr["data"]["version"]))] = 1
				outbox.pop_front()
				_save_cache()
				if not mine_already:
					note.emit("That battle had already been resolved on another device; this result was not used.", "warn")
				_t("online_battle_dropped" if not mine_already else "online_battle_confirmed", {"battle": bid})
				continue
		var outcome: Dictionary = item["outcome"]
		var nst := CTurn.apply_battle(st, bid, outcome)
		var text := CState.to_json(nst)
		var h := CState.hash_text(nst)
		var base := version
		var gz := gz64(text)
		item["base"] = base
		item["hash"] = h
		item["gz"] = gz
		_save_cache()
		var r := await _api("POST", "/state", {"base_version": base, "kind": "battle", "battle_id": bid,
			"outcome": outcome, "hash": h, "state_gz": gz, "rules": rules, "build": build}, {"retries": 2})
		if r["ok"]:
			outbox.pop_front()
			_leases.erase(bid)
			_t("online_battle_uploaded", {"battle": bid, "already": r["data"].get("already", false)})
			if version == base:
				_adopt(nst, int(r["data"]["version"]), h)
			else:
				_save_cache()
				sync()
			_outbox_backoff = 3.0
			continue
		if r["network"] or int(r["status"]) >= 500 or int(r["status"]) == 429:
			result = "network"
			_outbox_retry = _outbox_backoff
			_outbox_backoff = minf(_outbox_backoff * 2.0, 60.0)
			break
		var err := str(r["error"])
		if err == "conflict":
			if not await sync():
				result = "network"
				_outbox_retry = _outbox_backoff
				break
			continue  # re-checked against the newer state above
		if err == "claimed":
			result = "waiting"
			note.emit("Your ally is resolving this battle right now; your result is kept and sent if theirs does not arrive.", "warn")
			_outbox_retry = 20.0
			break
		# Anything else (bad state, no command): a bug or a rule change; keep
		# nothing that can never be accepted.
		outbox.pop_front()
		_save_cache()
		note.emit("The server refused the battle result (%s: %s)." % [err, str(r["message"])], "error")
		_t("online_error", {"what": "battle upload refused", "error": err, "message": str(r["message"])})
		result = err
	_flushing = false
	return result


func pending_upload(bid: int) -> bool:
	for it in outbox:
		if int(it["bid"]) == bid:
			return true
	return false


# --------------------------------------------------------- verification ---

## Re-run version v from its parent and inputs; report the result.
func verify(v: int) -> bool:
	if verified.has(str(v)):
		return int(verified[str(v)]) == 1
	var r := await _api("GET", "/history/%d?parent=1&state=0" % v)
	if not r["ok"]:
		return true
	var d: Dictionary = r["data"]
	var kind := str(d.get("kind", ""))
	if not (d.get("parent_state") is Dictionary) or not (d.get("inputs") is Dictionary):
		return true
	var parent: Dictionary = CState.normalise(d["parent_state"])
	var inputs: Dictionary = CState.normalise(d["inputs"])
	var t0 := Time.get_ticks_msec()
	var out: Dictionary
	if kind == "turn":
		out = CTurn.resolve_turn(parent, inputs.get("submissions", []))
	elif kind == "battle":
		out = CTurn.apply_battle(parent, int(inputs.get("battle_id", -1)), inputs.get("outcome", {}))
	else:
		return true
	var h := CState.hash_text(out)
	var ok := h == str(d.get("hash", ""))
	var ms := Time.get_ticks_msec() - t0
	verified[str(v)] = 1 if ok else 0
	_save_cache()
	await _api("POST", "/verify", {"version": v, "ok": ok, "local_hash": h, "ms": ms})
	_t("online_verify", {"version": v, "kind": kind, "ok": ok, "ms": ms})
	if not ok:
		_report_desync(v, h, str(d.get("hash", "")))
	return ok


func _report_desync(v: int, local_h: String, server_h: String) -> void:
	_t("online_desync", {"version": v, "local": local_h, "server": server_h, "rules": rules})
	desync.emit(v, local_h, server_h)
	note.emit("Warning: this device computed a different result for version %d (%s, the server has %s). The game rules differ between your devices; the server's copy is kept. Please report this." % [
		v, local_h, server_h], "error")


# ------------------------------------------------------------- settings ---

func make_link() -> Dictionary:
	return await _api("POST", "/link")


func settings(body: Dictionary) -> Dictionary:
	var r := await _api("POST", "/settings", body)
	await sync()
	return r


func test_notify() -> Dictionary:
	return await _api("POST", "/test-notify")


func history() -> Dictionary:
	return await _api("GET", "/history")


func rollback(to_version: int) -> Dictionary:
	var r := await _api("POST", "/rollback", {"to_version": to_version, "confirm": "rollback"})
	await sync()
	return r


# ---------------------------------------------------------------- cache ---

func _cache_file() -> String:
	return cache_dir + id + ".json"


func _load_cache() -> void:
	if not FileAccess.file_exists(_cache_file()):
		return
	var v = JSON.parse_string(FileAccess.get_file_as_string(_cache_file()))
	if not (v is Dictionary):
		return
	var d: Dictionary = CState.normalise(v)
	if d.get("state") is Dictionary and str(d["state"].get("format", "")) == CState.FORMAT \
			and int(d["state"].get("version", 0)) <= CState.VERSION \
			and int(d["state"].get("version", 0)) >= CState.MIN_VERSION:
		st = d["state"]
		version = int(d.get("version", 0))
		state_hash = CState.hash_text(st)
	if d.get("session") is Dictionary:
		session = d["session"]
	if d.get("outbox") is Array:
		outbox = d["outbox"]
	if d.get("mine") is Dictionary:
		mine = d["mine"]
	if d.get("verified") is Dictionary:
		verified = d["verified"]


func _save_cache() -> void:
	DirAccess.make_dir_recursive_absolute(cache_dir)
	# Keep the bookkeeping small: only recent versions.
	for table in [mine, verified]:
		for k in (table as Dictionary).keys():
			if int(k) < version - 40:
				(table as Dictionary).erase(k)
	var fa := FileAccess.open(_cache_file(), FileAccess.WRITE)
	if fa == null:
		return
	fa.store_string(JSON.stringify({"state": st, "version": version, "hash": state_hash, "session": session,
		"outbox": outbox, "mine": mine, "verified": verified}))
	fa.close()


## Delete the local cache (when the campaign is forgotten on this device).
func forget_cache() -> void:
	DirAccess.remove_absolute(_cache_file())
