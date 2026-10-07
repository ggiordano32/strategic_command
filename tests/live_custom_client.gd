extends SceneTree
## One player of the custom battle end-to-end test (run by
## tests/live_e2e.py): a custom battle room on the real server, with the
## game's own code (game/custom/custom_setup.gd, CoopSession in custom
## mode, sim/lockstep.gd). No view.
##
##   godot --headless --script res://tests/live_custom_client.gd -- --server=URL --role=A|B
##     --dir=DIR --mode=h2h|coop [--coop-frame-ms=20 --coop-hash-every=1]
##
## A (Player 1) creates the room from a setup (h2h: Player 2 commands the
## other side; coop: both on side 1 against the AI) and writes the code;
## B (Player 2) joins by code, adds a unit to its army (a setup change in
## the lobby: everyone's ready is cleared), both press Ready, A starts.
## Deployment phase (20 s): each places its units (orders for the other's
## units are refused), A readies early, B later; then both fight (attacks
## on the nearest enemy) to the end. Hashes every frame to
## <dir>/chashes_<mode>_<role>.json; <dir>/custom_<mode>_<role>.json the record.

const NetScript := preload("res://game/net/net.gd")
const CoopSession := preload("res://game/net/coop_session.gd")
const CS := preload("res://game/custom/custom_setup.gd")
const BattleSim := preload("res://sim/battle_sim.gd")

var role := "A"
var dir := ""
var mode := "h2h"
var net: NetScript
var result := {"errors": []}
var t0 := 0


func _initialize() -> void:
	_main.call_deferred()


func _log(s: String) -> void:
	print("[%s %s %6.1fs] %s" % [mode, role, (Time.get_ticks_msec() - t0) / 1000.0, s])


func _err(s: String) -> void:
	printerr("[%s %s] ERROR %s" % [mode, role, s])
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


func _setup() -> Dictionary:
	var st := CS.default_setup(4321)
	st["deploy"] = 20
	st["map"]["terrain"] = 1
	st["map"]["woods"] = 0
	var small := [["heavy", 80], ["spear", 80], ["archer", 60], ["cav", 40]]
	st["sides"][0]["armies"] = [{"ctrl": "p1", "units": small.duplicate(true)}]
	if mode == "h2h":
		st["sides"][1]["armies"] = [{"ctrl": "p2", "units": small.duplicate(true)}]
	else:
		st["sides"][0]["armies"].append({"ctrl": "p2", "units": [["pike", 100], ["javelin", 50]]})
		st["sides"][1]["armies"] = [{"ctrl": "ai", "units": [["heavy", 100], ["heavy", 100], ["spear", 100], ["archer", 80],
			["cav", 60]]}]
	return st


func _main() -> void:
	t0 = Time.get_ticks_msec()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--role="):
			role = a.get_slice("=", 1)
		elif a.begins_with("--dir="):
			dir = a.get_slice("=", 1)
		elif a.begins_with("--mode="):
			mode = a.get_slice("=", 1)
	net = NetScript.new()
	net.accounts_path = dir.path_join("cacc_%s_%s.json" % [mode, role])
	root.add_child(net)
	await process_frame
	if not await net.check_server() or int(net.info.get("api", 0)) < 3:
		_err("server not reachable or too old")
		_finish()
		return
	var code := ""
	var token := ""
	var me := 0 if role == "A" else 1
	if role == "A":
		var r: Dictionary = await net.api.call_api("POST", "/api/custom", {"setup": _setup(), "rules": net.rules,
			"build": net.build}, "", {})
		if not r["ok"]:
			_err("create: %s" % r)
			_finish()
			return
		code = str(r["data"]["code"])
		token = str(r["data"]["token"])
		_write("custom_%s_code.txt" % mode, code)
	else:
		code = await _wait_file("custom_%s_code.txt" % mode, 60.0)
		var r2: Dictionary = await net.api.call_api("POST", "/api/custom/join", {"code": code}, "", {})
		if not r2["ok"]:
			_err("join: %s" % r2)
			_finish()
			return
		token = str(r2["data"]["token"])
	var s := CoopSession.new()
	root.add_child(s)
	s.names = {0: "Player 1", 1: "Player 2"}
	s.setup_custom(net.api.base_url, code, token, me, func(st: Dictionary) -> Dictionary: return CS.build(st))
	s.note.connect(func(t: String, k: String): _log("note (%s): %s" % [k, t]))
	s.failed.connect(func(c: String, t: String): _err("room failed: %s %s" % [c, t]))
	# Lobby.
	var edited := false
	var revs := []
	var t_lobby := Time.get_ticks_msec()
	while s.ls == null and Time.get_ticks_msec() - t_lobby < 60000:
		await process_frame
		if s.phase != "lobby" or s.setup_data.is_empty():
			continue
		if not revs.has(s.setup_rev):
			revs.append(s.setup_rev)
		if role == "B" and not edited:
			# Player 2 adds a unit to its army (the host then sees rev 2).
			edited = true
			var st: Dictionary = s.setup_data.duplicate(true)
			for sd in st["sides"]:
				for a in sd["armies"]:
					if str(a["ctrl"]) == "p2":
						(a["units"] as Array).append(["javelin", 40])
			s.send_setup(st)
			continue
		if s.setup_rev < 2:
			continue
		if not s.want_ready and s.build_error == "":
			s.lobby_ready(true)
		if role == "A" and s.lobby_is_ready(0) and s.lobby_is_ready(1) and bool(s.player(1).get("on", false)):
			s.start_battle()
			await create_timer(0.3).timeout
	if s.ls == null:
		_err("the battle never started (phase %s, rev %d, build error %s)" % [s.phase, s.setup_rev, s.build_error])
		_finish()
		return
	result["revs"] = revs
	result["setup_rev"] = s.setup_rev
	var ls = s.ls
	var sim = ls.sim
	var my_side: int = ls.side_of(me)
	_log("battle started: rev %d, %d units, my side %d, AI sides %s, deploying %s" % [s.setup_rev, sim.n_units,
		my_side, str(sim.ai_sides), str(sim.phase == BattleSim.PHASE_DEPLOY)])
	var hashes := {}
	var placed := 0
	var tried_other := 0
	var ready_sent := false
	var start_frame := -1
	var end_frame := -1
	var t_start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t_start < 300000:
		await process_frame
		ls = s.ls
		sim = ls.sim
		for fr in s.my_hashes:
			hashes[fr] = s.my_hashes[fr]
		var fr0: int = ls.frame
		if sim.phase == BattleSim.PHASE_DEPLOY:
			if s.can_issue() and fr0 % 10 == 5 and s.get_meta("last", -1) != fr0 and fr0 < 120:
				s.set_meta("last", fr0)
				for u in sim.n_units:
					if s.can_order(u):
						s.issue({"type": BattleSim.ORDER_PLACE, "unit": u, "x": sim.u_ax[u] + ((fr0 / 10) % 3 - 1) * 4096,
							"y": sim.u_ay[u] + (1 if my_side == 0 else -1) * -10240, "facing": sim.u_face[u], "files": 10})
						placed += 1
						break
				for u in sim.n_units:
					if ls.u_cmd[u] >= 0 and ls.u_cmd[u] != me:
						s.issue({"type": BattleSim.ORDER_PLACE, "unit": u, "x": 5000, "y": 5000, "facing": 0, "files": 8})
						tried_other += 1
						break
			var ready_at := 40 if role == "A" else 90
			if fr0 >= ready_at and not ready_sent and s.can_issue():
				ready_sent = true
				s.issue({"type": BattleSim.ORDER_READY})
				_log("ready at frame %d" % fr0)
		elif start_frame < 0:
			start_frame = fr0
			_log("deployment over at frame %d (ready mask %d of %d)" % [fr0, sim.dep_ready, sim.dep_need])
		elif s.can_issue() and fr0 % 25 == 0 and s.get_meta("last", -1) != fr0:
			s.set_meta("last", fr0)
			_orders(s)
		if s.final_frame >= 0 and end_frame < 0:
			end_frame = s.final_frame
			_log("battle over at frame %d, tick %d, winner %d" % [end_frame, sim.tick, sim.winner])
		if end_frame >= 0 and fr0 >= end_frame + 15:
			break
	result["placed"] = placed
	result["tried_other"] = tried_other
	result["rejected"] = ls.rejected
	result["start_frame"] = start_frame
	result["end_frame"] = end_frame
	result["winner"] = ls.sim.winner
	result["my_side"] = my_side
	result["ai_sides"] = Array(ls.sim.ai_sides)
	result["result_hash"] = JSON.stringify(s.final_result).md5_text().substr(0, 8) if not s.final_result.is_empty() else ""
	result["stats"] = s.stats.duplicate()
	if end_frame < 0:
		_err("the battle did not end (frame %d)" % ls.frame)
	_write("chashes_%s_%s.json" % [mode, role], JSON.stringify(hashes))
	s.leave()
	await create_timer(0.8).timeout
	_finish()


func _finish() -> void:
	result["ok"] = (result["errors"] as Array).is_empty()
	_write("custom_%s_%s.json" % [mode, role], JSON.stringify(result, "  "))
	_log("done: %s" % ("ok" if result["ok"] else str(result["errors"])))
	quit(0 if result["ok"] else 1)


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
			s.issue(BattleSim.make_attack_order(0, u, best, 1))
