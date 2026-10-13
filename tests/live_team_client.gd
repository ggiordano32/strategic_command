extends SceneTree
## One player of the three-peer live battle end-to-end test (run by
## tests/live_team_e2e.py, which starts the Go server and three of these):
## a campaign battle with several humans (N-player campaigns). Uses the
## game's own code (Net / OnlineCampaign, CoopSession over real
## WebSockets); no battle view.
##
##   godot --headless --script res://tests/live_team_client.gd -- --server=URL --role=A|B|C --dir=DIR
##     [--coop-frame-ms=20 --coop-hash-every=1]
##
## A (Rome) creates a campaign of three humans: Rome and Carthage on one
## team, Macedon on its own, at war with both. One battle is pending: Rome's
## and Carthage's armies attack Macedon's capital, where a Macedonian army
## stands. B (Carthage) and C (Macedon) join with the same code. A opens the
## room; B (same side) and C (the other side) join; the host starts once
## all three are in. Each orders only the units it commands (scripted
## attacks); A gives B two units at frame 60 and B commands them; the host
## uploads the result once, the others see it come in. Every frame's
## lockstep hash goes to <dir>/thashes_<role>.json; <dir>/team_<role>.json
## has the numbers.

const NetScript := preload("res://game/net/net.gd")
const SelfTest := preload("res://game/net/net_selftest.gd")
const CoopSession := preload("res://game/net/coop_session.gd")
const BattleSim := preload("res://sim/battle_sim.gd")
const CData := preload("res://campaign/cdata.gd")
const CState := preload("res://campaign/cstate.gd")
const CRules := preload("res://campaign/crules.gd")
const CBattle := preload("res://campaign/cbattle.gd")

var role := "A"
var dir := ""
var net: NetScript
var oc = null
var cid := ""
var me := 0
var t0 := 0
var result := {"errors": []}


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


## The campaign: three humans, Rome + Carthage against Macedon at its
## capital (Macedon's army there too).
static func team_state() -> Dictionary:
	var rome := CData.faction_index("rome")
	var carth := CData.faction_index("carthage")
	var mace := CData.faction_index("macedon")
	var teams: Array = []
	for f in CData.faction_count():
		teams.append(f)
	teams[carth] = rome
	var st := CState.new_campaign("Live team E2E", 31, [rome, carth, mace], {"turn_timeout_h": 24}, teams)
	CState.set_dip(st, rome, mace, CState.WAR)
	CState.set_dip(st, carth, mace, CState.WAR)
	var r := int(CState.regions_of(st, mace)[0])
	var aa: Dictionary = SelfTest._clone_army(st, CState.armies_of(st, rome)[0], rome, r, 4)
	var ab: Dictionary = SelfTest._clone_army(st, CState.armies_of(st, carth)[0], carth, r, 4)
	SelfTest._clone_army(st, CState.armies_of(st, mace)[0], mace, r, 4)
	var b := CRules.start_battle(st, r, aa)
	(b["att"] as Array).append(int(ab["id"]))
	ab["busy"] = 1
	st["phase"] = "battles"
	st["settings"]["deploy_time"] = 0
	st["settings"]["time_limit"] = 360  # (6 min: the walled capital may hold; a draw ends it)
	return st


func _main() -> void:
	t0 = Time.get_ticks_msec()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--role="):
			role = a.get_slice("=", 1)
		elif a.begins_with("--dir="):
			dir = a.get_slice("=", 1)
	me = CData.faction_index({"A": "rome", "B": "carthage", "C": "macedon"}[role])
	net = NetScript.new()
	net.accounts_path = dir.path_join("tacc_%s.json" % role)
	net.cache_dir = dir.path_join("tcache_%s" % role) + "/"
	root.add_child(net)
	await process_frame
	if not await net.check_server():
		_err("server not reachable")
		_finish()
		return
	if role == "A":
		var r: Dictionary = await net.create_campaign(team_state(), me, {})
		if not r["ok"]:
			_err("create: %s" % r)
			_finish()
			return
		cid = str(r["data"]["id"])
		_write("tjoin.txt", str(r["data"]["join_code"]))
	else:
		var code := await _wait_file("tjoin.txt", 30.0)
		var r2: Dictionary = await net.join(code, me)
		if not r2["ok"]:
			_err("join: %s" % r2)
			_finish()
			return
		cid = str(r2["data"]["id"])
	oc = net.open_campaign(cid)
	await oc.open()
	var bid := int((oc.st["battles"] as Array)[0]["id"])
	await _battle(bid)
	for i in 100:
		await oc.sync()
		if str(oc.st["phase"]) != "battles":
			break
		await create_timer(0.2).timeout
	result["final"] = {"version": oc.version, "hash": oc.state_hash, "local_hash": CState.hash_text(oc.st),
		"phase": str(oc.st["phase"]), "outbox": oc.outbox.size()}
	_finish()


func _finish() -> void:
	result["ok"] = (result["errors"] as Array).is_empty()
	_write("team_%s.json" % role, JSON.stringify(result, "  "))
	_log("done: %s" % ("ok" if result["ok"] else str(result["errors"])))
	quit(0 if result["ok"] else 1)


func _battle(bid: int) -> void:
	var host := role == "A"
	if not host:
		await _wait_file("tlive_open.txt", 120.0)
		for i in 100:
			await oc.sync()
			if oc.battle_info(bid).get("live") is Dictionary:
				break
			await create_timer(0.1).timeout
		if not (oc.battle_info(bid).get("live") is Dictionary):
			_err("the summary never showed the battle live")
			return
	var b := CState.battle(oc.st, bid)
	var hs: Array = CRules.battle_humans(oc.st, b)
	result["humans"] = hs
	var built := CBattle.build(oc.st, b, int(hs.min()))
	var gl: Array = CoopSession.guest_list(oc.st, hs, b)
	var s := CoopSession.new()
	root.add_child(s)
	var e: Dictionary = net.accounts.get_entry(cid)
	s.setup(net.api.base_url, cid, str(e["token"]), me, built, hs, oc.version, host, false, gl,
		CoopSession.guest_sides(oc.st, b, built, gl))
	s.note.connect(func(t: String, k: String): _log("note (%s): %s" % [k, t]))
	s.failed.connect(func(c: String, t: String):
		if not s.result_in and s.final_frame < 0:
			_err("room failed: %s %s" % [c, t]))
	result["my_side"] = s.side_of_player(me)
	result["ai_sides"] = s.scenario.get("ai_sides", [])
	if host:
		_write("tlive_open.txt", "1")
	var hashes := {}
	var ended := false
	var end_frame := -1
	var gifted := {}
	var foreign_orders := 0
	var t_start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t_start < 400000:
		await process_frame
		if s.phase == "gone" and not ended:
			_err("session gone")
			break
		var ls = s.ls
		if ls == null:
			continue
		if not result.has("players"):
			result["players"] = Array(ls.active_players())
			result["start_frame"] = ls.frame
		for fr in s.my_hashes:
			hashes[fr] = s.my_hashes[fr]
		var fr0: int = ls.frame
		if s.can_issue() and fr0 % 25 == 0 and s.get_meta("last_orders", -1) != fr0:
			s.set_meta("last_orders", fr0)
			foreign_orders += _orders(s)
		_gift(s, gifted)
		if not result.has("own") and fr0 >= 30:
			# Each commands only its own units (and the keeper nobody's here).
			var own := 0
			var other := 0
			for u in ls.u_cmd.size():
				if ls.u_cmd[u] == me:
					if ls.u_home[u] == me:
						own += 1
					else:
						other += 1
			result["own"] = own
			result["other_at_30"] = other
		if s.final_frame >= 0 and end_frame < 0:
			end_frame = s.final_frame
			_log("battle over at frame %d, tick %d, winner %d" % [end_frame, ls.sim.tick, ls.sim.winner])
		if end_frame >= 0 and ls.frame >= end_frame + 15:
			ended = true
			break
	var ls2 = s.ls
	result["frames"] = ls2.frame if ls2 != null else -1
	result["winner"] = ls2.sim.winner if ls2 != null else -1
	result["stats"] = s.stats.duplicate()
	result["gifts"] = gifted
	result["foreign_orders"] = foreign_orders
	result["rejected"] = ls2.rejected if ls2 != null else -1
	result["ended"] = ended
	result["result_hash"] = JSON.stringify(s.final_result).md5_text().substr(0, 8) if not s.final_result.is_empty() else ""
	if not ended:
		_err("the battle did not end (frame %d)" % result["frames"])
	_write("thashes_%s.json" % role, JSON.stringify(hashes))
	if s.should_upload() and ended:
		s.announce_upload()
		var outcome := CBattle.outcome_from_result(built, s.final_result, "fought")
		outcome["live"] = 1
		var up: String = await oc.upload_battle(bid, outcome)
		result["upload"] = up
		_log("uploaded the result: %s" % up)
	else:
		for i in 300:
			await process_frame
			if s.result_in:
				break
			await create_timer(0.05).timeout
		result["result_in"] = s.result_in
	s.leave()
	await create_timer(0.8).timeout
	s.queue_free()


## Every 25 frames: each unit this player commands attacks the nearest
## enemy at a run. Returns 0 (orders only for commanded units).
func _orders(s) -> int:
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
			s.issue(BattleSim.make_attack_order(0, u, best, 1))
	return 0


## A gives its team-mate B two of its units at frame 60 (through the gift
## picker's list: teammates_in); B notes when it commands them.
func _gift(s, gifted: Dictionary) -> void:
	var ls = s.ls
	if not s.can_issue():
		return
	var fr: int = ls.frame
	var carth := CData.faction_index("carthage")
	var mace := CData.faction_index("macedon")
	if role == "A":
		if fr >= 60 and not gifted.has("given"):
			var mates: Array = s.teammates_in(me)
			gifted["mates"] = mates
			if not mates.has(carth) or mates.has(mace):
				_err("gift targets %s (want Carthage, never Macedon)" % str(mates))
			var units: Array = []
			for u in ls.u_cmd.size():
				if ls.u_cmd[u] == me and ls.sim.u_state[u] == BattleSim.U_READY and units.size() < 2:
					units.append(u)
			s.gift(units, carth)
			gifted["given"] = units
			gifted["given_at"] = fr
	elif role == "B":
		var n := 0
		for u in ls.u_cmd.size():
			if ls.u_cmd[u] == me and ls.u_home[u] == CData.faction_index("rome"):
				n += 1
		if n > 0 and not gifted.has("got"):
			gifted["got"] = n
			gifted["got_at"] = fr
