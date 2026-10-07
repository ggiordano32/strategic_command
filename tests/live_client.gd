extends SceneTree
## One player of the live co-op end-to-end test (run by tests/live_e2e.py,
## which starts the Go server and two of these). Uses the game's own code:
## Net / OnlineCampaign for the campaign, CoopSession (live_room.gd +
## sim/lockstep.gd) for the battles, against the real server over real
## WebSockets. No battle view: the session is driven like the view drives it.
##
##   godot --headless --script res://tests/live_client.gd -- --server=URL --role=A|B --dir=DIR
##     [--coop-frame-ms=20 --coop-hash-every=1 --coop-grace=2]
##
## A (Rome) creates a campaign whose state has three pending battles with
## both players' armies in them (net_selftest.gd live_test_state); B
## (Carthage) joins. Then:
##   battle 1 "prestart": A opens the room, B joins in the lobby, the host
##     starts when both are in; scripted orders on both sides, a gift A->B
##     and back, a pause vote (A asks, B accepts; resume the same), a speed
##     vote (B asks for 4x, A accepts); run to the end.
##   battle 2 "midjoin": A starts alone; B joins mid-battle (snapshot,
##     catch-up, ready, admitted) and takes command of its army.
##   battle 3 "drop": both start; B's connection drops at frame 200; A waits,
##     gets the Continue offer and takes over; B comes back (snapshot),
##     is admitted again and regains its units.
##   battle 4 "guest": Rome's army alone (Carthage has none there). B asks
##     to join (choice "ask"); A sees the request in the summary and opens
##     the room (Fight together); B joins as a guest; the host starts when
##     both are in; A gives B two units, B commands them; run to the end.
## Every frame's lockstep hash is recorded (hash_every 1) and written to
## <dir>/hashes_<role>_<battle>.json; the host uploads each result; both
## end on the same campaign state. <dir>/live_<role>.json has the numbers.

const NetScript := preload("res://game/net/net.gd")
const SelfTest := preload("res://game/net/net_selftest.gd")
const CoopSession := preload("res://game/net/coop_session.gd")
const Lockstep := preload("res://sim/lockstep.gd")
const BattleSim := preload("res://sim/battle_sim.gd")
const CData := preload("res://campaign/cdata.gd")
const CState := preload("res://campaign/cstate.gd")
const CRules := preload("res://campaign/crules.gd")
const CTurn := preload("res://campaign/cturn.gd")
const CBattle := preload("res://campaign/cbattle.gd")

var role := "A"
var dir := ""
var net: NetScript
var oc = null
var cid := ""
var me := 0
var ally := 1
var t0 := 0
var result := {"errors": [], "battles": []}
var hashes := {}


func _initialize() -> void:
	_main.call_deferred()


func _log(s: String) -> void:
	print("[%s %6.1fs] %s" % [role, (Time.get_ticks_msec() - t0) / 1000.0, s])


func _err(s: String) -> void:
	printerr("[%s] ERROR %s" % [role, s])
	(result["errors"] as Array).append(s)


func _write(fn: String, text: String) -> void:
	var f := FileAccess.open(dir.path_join(fn), FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _wait_file(fn: String, sec: float) -> String:
	var end := Time.get_ticks_msec() + int(sec * 1000.0)
	while Time.get_ticks_msec() < end:
		if FileAccess.file_exists(dir.path_join(fn)):
			return FileAccess.get_file_as_string(dir.path_join(fn)).strip_edges()
		await create_timer(0.05).timeout
	_err("timed out waiting for %s" % fn)
	return ""


func _main() -> void:
	t0 = Time.get_ticks_msec()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--role="):
			role = a.get_slice("=", 1)
		elif a.begins_with("--dir="):
			dir = a.get_slice("=", 1)
	var rome := CData.faction_index("rome")
	var carth := CData.faction_index("carthage")
	me = rome if role == "A" else carth
	ally = carth if role == "A" else rome
	net = NetScript.new()
	net.accounts_path = dir.path_join("acc_%s.json" % role)
	net.cache_dir = dir.path_join("cache_%s" % role) + "/"
	root.add_child(net)
	await process_frame
	if not await net.check_server():
		_err("server not reachable")
		_finish()
		return
	if role == "A":
		var st := SelfTest.live_test_state("Live E2E", 21, rome, carth, [7, 11, 13], 4)
		# Battle 4: Rome's army alone at Emporion (independent).
		var ga: Dictionary = SelfTest._clone_army(st, CState.armies_of(st, rome)[0], rome, 15, 4)
		CRules.start_battle(st, 15, ga)
		# Battles with a 10 s deployment phase (the campaign setting).
		st["settings"]["deploy_time"] = 10
		var r: Dictionary = await net.create_campaign(st, rome, {})
		if not r["ok"]:
			_err("create: %s" % r)
			_finish()
			return
		cid = str(r["data"]["id"])
		_write("join.txt", str(r["data"]["join_code"]))
	else:
		var code := await _wait_file("join.txt", 30.0)
		var r2: Dictionary = await net.join(code, carth)
		if not r2["ok"]:
			_err("join: %s" % r2)
			_finish()
			return
		cid = str(r2["data"]["id"])
	oc = net.open_campaign(cid)
	await oc.open()
	_log("campaign %s v%d, %d battles pending" % [cid, oc.version, (oc.st["battles"] as Array).size()])
	var ids: Array = []
	for b in oc.st["battles"]:
		ids.append(int(b["id"]))
	ids.sort()
	var kinds := ["prestart", "midjoin", "drop", "guest"]
	for k in mini(ids.size(), 4):
		await _battle(kinds[k], int(ids[k]))
	# Both end on the server's state.
	for i in 100:
		await oc.sync()
		if str(oc.st["phase"]) != "battles":
			break
		await create_timer(0.2).timeout
	result["final"] = {"version": oc.version, "hash": oc.state_hash, "local_hash": CState.hash_text(oc.st),
		"phase": str(oc.st["phase"]), "outbox": oc.outbox.size(), "verified": oc.verified}
	_finish()


func _finish() -> void:
	result["ok"] = (result["errors"] as Array).is_empty()
	_write("live_%s.json" % role, JSON.stringify(result, "  "))
	_log("done: %s" % ("ok" if result["ok"] else str(result["errors"])))
	quit(0 if result["ok"] else 1)


# --------------------------------------------------------------- battles ---

func _battle(kind: String, bid: int) -> void:
	_log("battle %d: %s" % [bid, kind])
	await oc.sync()
	var b := CState.battle(oc.st, bid)
	if b.is_empty():
		_err("battle %d not pending" % bid)
		return
	var host := role == "A"
	var rec := {"kind": kind, "battle": bid}
	if kind == "guest":
		# B (no army here) asks to join; A sees it before opening the room.
		if not host:
			var r: Dictionary = await oc.choose(bid, "ask")
			rec["asked"] = bool(r["ok"])
			if not r["ok"]:
				_err("battle %d: ask refused %s" % [bid, r])
			_write("live_%d_asked.txt" % bid, "1")
		else:
			await _wait_file("live_%d_asked.txt" % bid, 120.0)
			for i in 100:
				await oc.sync()
				var asks: Array = oc.battle_info(bid).get("ask_by", [])
				if asks.has(float(ally)) or asks.has(ally):
					rec["ask_seen"] = true
					break
				await create_timer(0.1).timeout
			if not rec.has("ask_seen"):
				_err("battle %d: the owner never saw the request to join" % bid)
	# The peer waits for the host's room (and for the mid-battle point).
	if not host:
		var need := "live_%d_open" % bid
		if kind == "midjoin":
			need = "live_%d_frame150" % bid
		await _wait_file(need + ".txt", 120.0)
		for i in 50:
			await oc.sync()
			if oc.battle_info(bid).get("live") is Dictionary:
				break
			await create_timer(0.1).timeout
		if not (oc.battle_info(bid).get("live") is Dictionary):
			_err("battle %d: the summary never showed it live" % bid)
	var v: int = oc.version
	var bst: Dictionary = oc.st
	var live = oc.battle_info(bid).get("live")
	if not host and live is Dictionary and int(live["version"]) != v:
		v = int(live["version"])
		bst = await oc.state_at(v)
	var hs: Array = CRules.battle_humans(bst, CState.battle(bst, bid))
	var built := CBattle.build(bst, CState.battle(bst, bid), int(hs.min()))
	var guests: Array = CoopSession.guest_list(bst, hs)
	rec["guests"] = guests
	if kind == "guest" and (hs != [rome_f()] or guests != [carth_f()]):
		_err("battle %d: humans %s guests %s" % [bid, hs, guests])
	var s := _session(built, hs, v, host, guests)
	if host and kind == "midjoin":
		s.auto_start = false
	if host:
		_write("live_%d_open.txt" % bid, "1")
	var hkey := "%s_%d" % [role, bid]
	hashes[hkey] = {}
	var dropped_at := -1
	var rejoined := false
	var took := -1
	var regained := -1
	var started_ms := -1
	var ended := false
	var t_start := Time.get_ticks_msec()
	var gifted := {}
	var votes := {"pause_asked": -1, "pause_on": -1, "resume_asked": -1, "resume_on": -1, "speed_asked": -1, "speed_on": -1}
	var end_frame := -1
	while Time.get_ticks_msec() - t_start < 400000:
		await process_frame
		if s.phase == "gone" and not ended:
			_err("battle %d: session gone (%s)" % [bid, kind])
			break
		var ls = s.ls
		if host and kind == "midjoin" and s.phase == "lobby" and s.room.is_open():
			s.start_battle()
		if ls == null:
			continue
		if started_ms < 0:
			started_ms = Time.get_ticks_msec()
		if ls.sim.dep_on != 0 and ls.sim.phase == BattleSim.PHASE_BATTLE and not rec.has("deploy_end"):
			rec["deploy_end"] = ls.frame
		if kind == "prestart" and role == "A" and ls.frame >= 30 and not rec.has("ready_sent") and s.can_issue() \
				and ls.sim.phase == BattleSim.PHASE_DEPLOY:
			rec["ready_sent"] = ls.frame
			s.issue({"type": BattleSim.ORDER_READY})
		for fr in s.my_hashes:
			hashes[hkey][fr] = s.my_hashes[fr]
		var fr0: int = ls.frame
		if host and kind == "midjoin" and fr0 >= 150 and not FileAccess.file_exists(dir.path_join("live_%d_frame150.txt" % bid)):
			_write("live_%d_frame150.txt" % bid, "1")
		# Scripted play.
		if s.can_issue() and fr0 % 25 == 0 and s.get_meta("last_orders", -1) != fr0:
			s.set_meta("last_orders", fr0)
			_orders(s)
		if kind == "prestart":
			_controls(s, votes, gifted)
		if kind == "guest":
			_guest(s, gifted)
		# Battle 3: B drops at frame 200, comes back 120 frames of A later.
		if kind == "drop" and not host and dropped_at < 0 and fr0 >= 200 and s.ls.is_active(me):
			dropped_at = fr0
			_log("dropping the connection at frame %d" % fr0)
			s.room.close()
			s.queue_free()
			_write("live_%d_dropped.txt" % bid, str(fr0))
			await _wait_file("live_%d_took.txt" % bid, 120.0)
			await create_timer(1.0).timeout
			s = _session(built, hs, v, false, guests)
			rejoined = true
			continue
		if kind == "drop" and host and s.takeover_offer >= 0 and took < 0:
			took = fr0
			_log("taking over from %s at frame %d (waited %.1f s)" % [CData.faction_name(s.takeover_offer), fr0, s.wait_sec])
			s.continue_without(s.takeover_offer)
		if kind == "drop" and host and took >= 0 and not FileAccess.file_exists(dir.path_join("live_%d_took.txt" % bid)):
			if not ls.is_active(ally) and _count_cmd(ls, me, ally) > 0:
				rec["took_units"] = _count_cmd(ls, me, ally)
				_write("live_%d_took.txt" % bid, str(fr0))
		if kind == "drop" and rejoined and regained < 0 and ls.is_active(me) and _count_cmd(ls, me, me) > 0:
			regained = fr0
			rec["regained_units"] = _count_cmd(ls, me, me)
			_log("back in command of %d units at frame %d" % [rec["regained_units"], fr0])
		if kind == "midjoin" and not host and ls.is_active(me) and not rec.has("admitted_frame"):
			rec["admitted_frame"] = fr0
			rec["commands"] = _count_cmd(ls, me, me)
		if s.final_frame >= 0 and end_frame < 0:
			end_frame = s.final_frame
			_log("battle over at frame %d, tick %d, winner %d" % [end_frame, ls.sim.tick, ls.sim.winner])
		if end_frame >= 0 and ls.frame >= end_frame + 15:
			ended = true
			break
	var ls2 = s.ls
	rec["frames"] = ls2.frame if ls2 != null else -1
	rec["tick"] = ls2.sim.tick if ls2 != null else -1
	rec["winner"] = ls2.sim.winner if ls2 != null else -1
	rec["final_hash"] = "%08x" % ls2.state_hash() if ls2 != null else ""
	rec["stats"] = s.stats.duplicate()
	rec["rtt_ms"] = s.room.srtt_ms
	rec["delay"] = s.delay
	rec["votes"] = votes
	rec["gifts"] = gifted
	rec["desync_log"] = s.desync_log
	rec["wall_s"] = (Time.get_ticks_msec() - t_start) / 1000.0
	rec["result_hash"] = JSON.stringify(s.final_result).md5_text().substr(0, 8) if not s.final_result.is_empty() else ""
	rec["ended"] = ended
	if not ended:
		_err("battle %d (%s) did not end (frame %d)" % [bid, kind, rec["frames"]])
	_write("hashes_%s_%d.json" % [role, bid], JSON.stringify(hashes[hkey]))
	# Result: the host uploads; the other waits for it.
	if s.should_upload() and ended:
		s.announce_upload()
		var outcome := CBattle.outcome_from_result(built, s.final_result, "fought")
		outcome["live"] = 1
		var up: String = await oc.upload_battle(bid, outcome)
		rec["upload"] = up
		_log("uploaded the result: %s" % up)
	else:
		for i in 300:
			await process_frame
			if s.result_in:
				break
			await create_timer(0.05).timeout
		rec["result_in"] = s.result_in
	s.leave()
	await create_timer(0.8).timeout
	s.queue_free()
	for i in 100:
		await oc.sync()
		if CState.battle(oc.st, bid).is_empty():
			break
		await create_timer(0.1).timeout
	if not CState.battle(oc.st, bid).is_empty():
		_err("battle %d still pending after the result" % bid)
	(result["battles"] as Array).append(rec)


func _session(built: Dictionary, hs: Array, v: int, create: bool, guests: Array = []) -> Node:
	var s := CoopSession.new()
	root.add_child(s)
	var e: Dictionary = net.accounts.get_entry(cid)
	s.setup(net.api.base_url, cid, str(e["token"]), me, built, hs, v, create, false, guests)
	s.note.connect(func(t: String, k: String): _log("note (%s): %s" % [k, t]))
	s.failed.connect(func(c: String, t: String):
		if not s.result_in and s.final_frame < 0:
			_err("room failed: %s %s" % [c, t]))
	return s


func _count_cmd(ls, cmd: int, home: int) -> int:
	var c := 0
	for u in ls.u_cmd.size():
		if ls.u_cmd[u] == cmd and ls.u_home[u] == home:
			c += 1
	return c


## Every 25 frames: each of my ready units attacks the nearest enemy (at a
## run, so battles end), now and then a move instead.
func _orders(s) -> void:
	var sim = s.ls.sim
	for u in sim.n_units:
		if not s.can_order(u) or sim.u_state[u] != BattleSim.U_READY:
			continue
		var best := -1
		var bd := 0
		for t in sim.n_units:
			if sim.u_side[t] == sim.u_side[u] or sim.u_state[t] != BattleSim.U_READY:
				continue
			var dx: int = sim.u_cx[t] - sim.u_cx[u]
			var dy: int = sim.u_cy[t] - sim.u_cy[u]
			var d := dx * dx / 1024 + dy * dy / 1024
			if best < 0 or d < bd:
				best = t
				bd = d
		if best >= 0:
			if (u + s.ls.frame / 25) % 7 == 3:
				s.issue(BattleSim.make_move_order(0, u, sim.u_ax[u] + 3 * 1024, sim.u_ay[u] - 10 * 1024, 768, 30 * 1024, 0))
			else:
				s.issue(BattleSim.make_attack_order(0, u, best, 1))


func rome_f() -> int:
	return CData.faction_index("rome")


func carth_f() -> int:
	return CData.faction_index("carthage")


## Battle 4: the owner (A) gives the guest (B) two units at frame 60; B
## notes when it commands them and when it has ordered them.
func _guest(s, gifted: Dictionary) -> void:
	var ls = s.ls
	if not s.can_issue():
		return
	var fr: int = ls.frame
	if role == "A":
		if fr >= 60 and not gifted.has("given"):
			var units: Array = []
			for u in ls.u_cmd.size():
				if ls.u_cmd[u] == me and ls.sim.u_state[u] == BattleSim.U_READY and units.size() < 2:
					units.append(u)
			if not units.is_empty():
				s.gift(units, ally)
				gifted["given"] = units
				gifted["given_at"] = fr
		if gifted.has("given") and not gifted.has("ally_has"):
			var n := 0
			for u in gifted["given"]:
				if ls.u_cmd[int(u)] == ally:
					n += 1
			if n > 0:
				gifted["ally_has"] = n
				gifted["ally_has_at"] = fr
	else:
		var n2 := _count_cmd(ls, me, ally)
		if n2 > 0 and not gifted.has("got"):
			gifted["got"] = n2
			gifted["got_at"] = fr
		if gifted.has("got") and not gifted.has("ordered") and fr % 25 == 0:
			gifted["ordered"] = fr  # (_orders ran this frame for the units it commands)


## Battle 1's gifts and votes.
func _controls(s, votes: Dictionary, gifted: Dictionary) -> void:
	var ls = s.ls
	if not s.can_issue():
		return
	var fr: int = ls.frame
	if role == "A":
		if fr >= 60 and not gifted.has("given"):
			for u in ls.u_cmd.size():
				if ls.u_cmd[u] == me and ls.sim.u_state[u] == BattleSim.U_READY:
					s.gift([u], ally)
					gifted["given"] = u
					gifted["given_at"] = fr
					break
		if fr >= 90 and votes["pause_asked"] < 0:
			votes["pause_asked"] = fr
			s.request_pause()
		if votes["pause_on"] >= 0 and fr >= votes["pause_on"] + 20 and votes["resume_asked"] < 0:
			votes["resume_asked"] = fr
			s.request_pause()
		if ls.vote_speed_by == ally and votes["speed_asked"] < 0:
			votes["speed_asked"] = fr
			s.answer(1, true)
	else:
		if gifted.is_empty():
			for u in ls.u_cmd.size():
				if ls.u_cmd[u] == me and ls.u_home[u] == ally:
					gifted["got"] = u
					gifted["got_at"] = fr
					break
		elif gifted.has("got") and not gifted.has("back") and fr >= int(gifted["got_at"]) + 20:
			s.gift([int(gifted["got"])], ally)
			gifted["back"] = fr
		if ls.vote_pause_by == ally and s.get_meta("answered_pause", -1) != ls.vote_pause_want:
			s.set_meta("answered_pause", ls.vote_pause_want)
			s.answer(0, true)
		if fr >= 140 and votes["speed_asked"] < 0:
			votes["speed_asked"] = fr
			s.request_speed(16)
	if ls.paused == 1 and votes["pause_on"] < 0:
		votes["pause_on"] = fr
	if votes["pause_on"] >= 0 and ls.paused == 0 and votes["resume_on"] < 0:
		votes["resume_on"] = fr
	if ls.speed_q == 16 and votes["speed_on"] < 0:
		votes["speed_on"] = fr
	if role == "A" and gifted.has("given") and not gifted.has("back_at") and ls.u_cmd[int(gifted["given"])] == me \
			and fr > int(gifted["given_at"]) + 5:
		gifted["back_at"] = fr
