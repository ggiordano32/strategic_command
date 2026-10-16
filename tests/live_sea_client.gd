extends SceneTree
## One player of the live co-op sea battle end-to-end test (run by
## tests/live_e2e.py --only-sea / in its full run, which starts the Go server
## and two of these). Uses the game's own code: Net / OnlineCampaign for the
## campaign, CoopSession (live_room.gd + sim/lockstep.gd running the SeaSim)
## for the battles, CSeaBattle for the scenario and the outcome, against the
## real server over real WebSockets. No battle view: the session is driven
## like game/sea_battle.gd drives it.
##
##   godot --headless --script res://tests/live_sea_client.gd -- --server=URL --role=A|B --dir=DIR
##     [--coop-frame-ms=20 --coop-hash-every=1 --coop-grace=2]
##
## A (England) creates a West campaign whose state has two pending sea
## battles, each with an English and a Dutch fleet attacking a Spanish one
## (the battle AI); B (the Dutch) joins. Then:
##   battle 1 "prestart": A opens the room, B joins in the lobby, the host
##     starts when both are in; each player sends their own ships at the
##     nearest enemy (engage, now and then board); A gives B a ship and B
##     gives it back; a pause vote (A asks, B accepts; resume the same); a
##     speed vote (B asks for 4x, A accepts); run to the end.
##   battle 2 "midjoin": A starts alone; B joins mid-battle (snapshot,
##     catch-up, ready, admitted) and takes command of its ships.
## Every frame's lockstep hash is written to <dir>/sea_hashes_<role>_<battle>.json;
## the host uploads each result (CSeaBattle.outcome_from_result); both end
## on the same campaign state. <dir>/sea_<role>.json has the numbers.

const NetScript := preload("res://game/net/net.gd")
const CoopSession := preload("res://game/net/coop_session.gd")
const Lockstep := preload("res://sim/lockstep.gd")
const SeaSim := preload("res://sim/sea_sim.gd")
const CData := preload("res://campaign/cdata.gd")
const CState := preload("res://campaign/cstate.gd")
const CRules := preload("res://campaign/crules.gd")
const CGrid := preload("res://campaign/cgrid.gd")
const CFleet := preload("res://campaign/cfleet.gd")
const CSeaBattle := preload("res://campaign/cseabattle.gd")

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


## A West campaign with England and the Dutch human, and two pending sea
## battles: an English and a Dutch fleet attacking a Spanish one each, on
## open sea cells (pure: both roles could build it; A uploads it).
static func sea_test_state(nm: String, sd: int) -> Dictionary:
	CData.use_pack("west")
	var eng := CData.faction_index("england")
	var dut := CData.faction_index("dutch")
	var sp := CData.faction_index("new_spain")
	var st: Dictionary = CState.new_campaign(nm, sd, [eng, dut], {"turn_timeout_h": 24}, [], "west")
	st["fleets"] = []
	var spots: Array = []
	for c in CGrid.count():
		if spots.size() >= 2:
			break
		if not CFleet.is_sea(c) or CFleet.coast_dist(c) < 3 or CGrid.cy(c) < 20 or CGrid.cx(c) < 60 or CGrid.cx(c) > 120:
			continue
		var far := true
		for o in spots:
			if CGrid.cheb(int(o), c) < 12:
				far = false
		if far:
			spots.append(c)
	var fid := 900
	for c in spots:
		var x := CGrid.cx(c)
		var y := CGrid.cy(c)
		var e1 := {"id": fid, "f": eng, "x": x, "y": y, "ships": [{"t": "frigate", "h": 100, "c": 100}, {"t": "sloop", "h": 100, "c": 100}],
			"carry": [], "moved": 1}
		var e2 := {"id": fid + 1, "f": dut, "x": x, "y": y, "ships": [{"t": "frigate", "h": 100, "c": 100},
			{"t": "fire_ship", "h": 100, "c": 100}], "carry": [], "moved": 1}
		var e3 := {"id": fid + 2, "f": sp, "x": x, "y": y, "ships": [{"t": "galleon", "h": 80, "c": 70}, {"t": "sloop", "h": 90, "c": 90}],
			"carry": [], "moved": 0}
		st["fleets"].append(e1)
		st["fleets"].append(e2)
		st["fleets"].append(e3)
		CFleet._pending(st, [e1, e2], [e3], c)
		fid += 10
	st["phase"] = "battles"
	return st


func _main() -> void:
	t0 = Time.get_ticks_msec()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--role="):
			role = a.get_slice("=", 1)
		elif a.begins_with("--dir="):
			dir = a.get_slice("=", 1)
	CData.use_pack("west")
	var eng := CData.faction_index("england")
	var dut := CData.faction_index("dutch")
	me = eng if role == "A" else dut
	ally = dut if role == "A" else eng
	net = NetScript.new()
	net.accounts_path = dir.path_join("sacc_%s.json" % role)
	net.cache_dir = dir.path_join("scache_%s" % role) + "/"
	root.add_child(net)
	await process_frame
	if not await net.check_server():
		_err("server not reachable")
		_finish()
		return
	if role == "A":
		var st := sea_test_state("Live Sea E2E", 31)
		var r: Dictionary = await net.create_campaign(st, eng, {})
		if not r["ok"]:
			_err("create: %s" % r)
			_finish()
			return
		cid = str(r["data"]["id"])
		_write("sea_join.txt", str(r["data"]["join_code"]))
	else:
		var code := await _wait_file("sea_join.txt", 60.0)
		var r2: Dictionary = await net.join(code, dut)
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
	var kinds := ["prestart", "midjoin"]
	if ids.size() != 2:
		_err("expected two pending sea battles, got %d" % ids.size())
	for k in mini(ids.size(), 2):
		await _battle(kinds[k], int(ids[k]))
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
	_write("sea_%s.json" % role, JSON.stringify(result, "  "))
	_log("done: %s" % ("ok" if result["ok"] else str(result["errors"])))
	quit(0 if result["ok"] else 1)


func _battle(kind: String, bid: int) -> void:
	_log("sea battle %d: %s" % [bid, kind])
	await oc.sync()
	var b := CState.battle(oc.st, bid)
	if b.is_empty() or not b.has("sea"):
		_err("sea battle %d not pending" % bid)
		return
	var host := role == "A"
	var rec := {"kind": kind, "battle": bid}
	if not host:
		var need := "sea_%d_open" % bid
		if kind == "midjoin":
			need = "sea_%d_frame150" % bid
		await _wait_file(need + ".txt", 120.0)
		for i in 50:
			await oc.sync()
			if oc.battle_info(bid).get("live") is Dictionary:
				break
			await create_timer(0.1).timeout
		if not (oc.battle_info(bid).get("live") is Dictionary):
			_err("sea battle %d: the summary never showed it live" % bid)
	var v: int = oc.version
	var bst: Dictionary = oc.st
	var live = oc.battle_info(bid).get("live")
	if not host and live is Dictionary and int(live["version"]) != v:
		v = int(live["version"])
		bst = await oc.state_at(v)
	var hs: Array = CRules.battle_humans(bst, CState.battle(bst, bid))
	if hs.size() != 2:
		_err("sea battle %d: humans %s" % [bid, hs])
	var built := CSeaBattle.build(bst, CState.battle(bst, bid), int(hs.min()))
	var s := _session(built, hs, v, host)
	if host and kind == "midjoin":
		s.auto_start = false
	if host:
		_write("sea_%d_open.txt" % bid, "1")
	var hkey := "%s_%d" % [role, bid]
	hashes[hkey] = {}
	var ended := false
	var t_start := Time.get_ticks_msec()
	var gifted := {}
	var votes := {"pause_asked": -1, "pause_on": -1, "resume_asked": -1, "resume_on": -1, "speed_asked": -1, "speed_on": -1}
	var end_frame := -1
	while Time.get_ticks_msec() - t_start < 400000:
		await process_frame
		if s.phase == "gone" and not ended:
			_err("sea battle %d: session gone (%s)" % [bid, kind])
			break
		var ls = s.ls
		if host and kind == "midjoin" and s.phase == "lobby" and s.room.is_open():
			s.start_battle()
		if ls == null:
			continue
		if not (ls.sim is SeaSim):
			_err("sea battle %d: the lockstep does not run the sea sim" % bid)
			break
		for fr in s.my_hashes:
			hashes[hkey][fr] = s.my_hashes[fr]
		var fr0: int = ls.frame
		if host and kind == "midjoin" and fr0 >= 150 and not FileAccess.file_exists(dir.path_join("sea_%d_frame150.txt" % bid)):
			_write("sea_%d_frame150.txt" % bid, "1")
		if s.can_issue() and fr0 % 25 == 0 and s.get_meta("last_orders", -1) != fr0:
			s.set_meta("last_orders", fr0)
			_orders(s)
		if kind == "prestart":
			_controls(s, votes, gifted)
		if kind == "midjoin" and not host and ls.is_active(me) and not rec.has("admitted_frame"):
			rec["admitted_frame"] = fr0
			rec["commands"] = _count_cmd(ls, me, me)
		if s.final_frame >= 0 and end_frame < 0:
			end_frame = s.final_frame
			_log("over at frame %d, tick %d, winner %d" % [end_frame, ls.sim.tick, ls.sim.winner])
		if end_frame >= 0 and ls.frame >= end_frame + 15:
			ended = true
			break
	var ls2 = s.ls
	rec["frames"] = ls2.frame if ls2 != null else -1
	rec["tick"] = ls2.sim.tick if ls2 != null else -1
	rec["winner"] = ls2.sim.winner if ls2 != null else -1
	rec["stats"] = s.stats.duplicate()
	rec["sim_stats"] = ls2.sim.stats.duplicate() if ls2 != null else {}
	rec["rtt_ms"] = s.room.srtt_ms
	rec["votes"] = votes
	rec["gifts"] = gifted
	rec["wall_s"] = (Time.get_ticks_msec() - t_start) / 1000.0
	rec["result_hash"] = JSON.stringify(s.final_result).md5_text().substr(0, 8) if not s.final_result.is_empty() else ""
	rec["ended"] = ended
	if not ended:
		_err("sea battle %d (%s) did not end (frame %d)" % [bid, kind, rec["frames"]])
	_write("sea_hashes_%s_%d.json" % [role, bid], JSON.stringify(hashes[hkey]))
	if s.should_upload() and ended:
		s.announce_upload()
		var outcome := CSeaBattle.outcome_from_result(built, s.final_result, "fought")
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
		_err("sea battle %d still pending after the result" % bid)
	(result["battles"] as Array).append(rec)


func _session(built: Dictionary, hs: Array, v: int, create: bool) -> Node:
	var s := CoopSession.new()
	root.add_child(s)
	var e: Dictionary = net.accounts.get_entry(cid)
	s.setup(net.api.base_url, cid, str(e["token"]), me, built, hs, v, create, false, [])
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


## Every 25 frames: each of my ships fighting engages the nearest enemy
## (the fire ship is sent at her; now and then a ship boards instead).
func _orders(s) -> void:
	var sim = s.ls.sim
	for u in sim.n_units:
		if not s.can_order(u) or sim.u_state[u] != SeaSim.S_SAIL:
			continue
		var best := -1
		var bd := 0
		for t in sim.n_units:
			if sim.u_side[t] == sim.u_side[u] or sim.u_state[t] != SeaSim.S_SAIL:
				continue
			var d: int = absi(sim.s_x[t] - sim.s_x[u]) / 1024 + absi(sim.s_y[t] - sim.s_y[u]) / 1024
			if best < 0 or d < bd:
				best = t
				bd = d
		if best >= 0:
			var typ := SeaSim.O_BOARD if (u + s.ls.frame / 25) % 5 == 2 else SeaSim.O_TARGET
			s.issue({"type": typ, "unit": u, "target": best})


## Battle 1's gift (A gives B a ship, B gives it back) and votes.
func _controls(s, votes: Dictionary, gifted: Dictionary) -> void:
	var ls = s.ls
	if not s.can_issue():
		return
	var fr: int = ls.frame
	if role == "A":
		if fr >= 60 and not gifted.has("given"):
			for u in ls.u_cmd.size():
				if ls.u_cmd[u] == me and ls.sim.u_state[u] == SeaSim.S_SAIL:
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
