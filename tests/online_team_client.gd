extends SceneTree
## One player of the 3-human online test (run by tests/online_e2e.py --teams):
##   godot --headless --script res://tests/online_team_client.gd -- --server=URL
##     --role=A|B|C --dir=/tmp/x [--turns=2]
## A (Rome) creates a campaign with three humans (Rome and Carthage on one
## team, Macedon alone) and writes the join code; B (Carthage) and C
## (Macedon) join with the SAME code, each picking a different free seat.
## Every client plans with tests/online_policy.gd (builds and recruits, no
## attacks) and submits; the last submitter resolves. C also proposes that
## Rome join its team on turn 1 (a human target: a proposal for next turn).
## Writes <dir>/result_<role>.json; exit code 0 on success.

const NetScript := preload("res://game/net/net.gd")
const OnlineCampaign := preload("res://game/net/online_campaign.gd")
const Policy := preload("res://tests/online_policy.gd")
const CData := preload("res://campaign/cdata.gd")
const CState := preload("res://campaign/cstate.gd")
const CBattle := preload("res://campaign/cbattle.gd")
const BattleSim := preload("res://sim/battle_sim.gd")

var role := "A"
var dir := ""
var turns := 2
var me := 0
var net: NetScript
var oc: OnlineCampaign
var cid := ""
var changes := 0
var result := {"submissions": {}, "errors": [], "battles": 0}


func _initialize() -> void:
	_main.call_deferred()


func _log(s: String) -> void:
	print("[%s] %s" % [role, s])


func _err(s: String) -> void:
	printerr("[%s] ERROR %s" % [role, s])
	(result["errors"] as Array).append(s)


func _main() -> void:
	for a in OS.get_cmdline_user_args():
		var v: String = a.get_slice("=", 1)
		if a.begins_with("--role="):
			role = v
		elif a.begins_with("--dir="):
			dir = v
		elif a.begins_with("--turns="):
			turns = int(v)
	var rome := CData.faction_index("rome")
	var carthage := CData.faction_index("carthage")
	var macedon := CData.faction_index("macedon")
	me = {"A": rome, "B": carthage, "C": macedon}[role]
	net = NetScript.new()
	net.accounts_path = dir.path_join("acc_" + role + ".json")
	root.add_child(net)
	await process_frame
	if role == "A":
		var teams: Array = []
		for f in CData.faction_count():
			teams.append(f)
		teams[carthage] = rome
		var st := CState.new_campaign("E2E3", 21, [rome, carthage, macedon], {"turn_timeout_h": 0}, teams)
		var r: Dictionary = await net.create_campaign(st, rome, {})
		if not r["ok"]:
			_err("create: %s" % r)
			await _finish()
			return
		cid = str(r["data"]["id"])
		_write("join.txt", str(r["data"]["join_code"]))
		_log("created %s, code %s" % [cid, r["data"]["join_code"]])
	else:
		var code := await _wait_file("join.txt", 30.0)
		var pv: Dictionary = await net.join_preview(code)
		var free: Array = []
		if pv["ok"]:
			for seat in pv["data"]["seats"]:
				if not bool(seat["claimed"]):
					free.append(int(seat["f"]))
		if not pv["ok"] or (pv["data"]["seats"] as Array).size() != 3 or not free.has(me):
			_err("join preview: %s (free %s)" % [pv, free])
			await _finish()
			return
		var r: Dictionary = await net.join(code, me, "")
		if not r["ok"]:
			_err("join: %s" % r)
			await _finish()
			return
		cid = str(r["data"]["id"])
		_log("joined %s as %s" % [cid, CData.faction_name(me)])
	oc = net.open_campaign(cid)
	oc.cache_dir = dir.path_join("cache_" + role) + "/"
	oc.resolve_grace = 3.0
	oc.changed.connect(func(_w): changes += 1)
	oc.desync.connect(func(v, a, b): _err("desync at version %d: %s vs %s" % [v, a, b]))
	await oc.open()
	await _play()
	await _finish()


func _play() -> void:
	var guard := 0
	while guard < 4000:
		guard += 1
		await oc.sync()
		var st := oc.st
		var t := int(st["turn"])
		var ph := str(st["phase"])
		if ph == "over" or (t >= turns and ph == "plan"):
			_log("done at turn %d" % t)
			break
		if ph == "battles":
			if not await _battles():
				await _wait_change(1.0)
			continue
		if oc.i_submitted() or (oc.summary.get("seats", []) as Array).any(func(s): return not bool(s["claimed"])):
			await _wait_change(1.0)
			continue
		var orders := Policy.plan(st, me, 100000, false)
		if role == "C" and t == 0:
			orders.append({"t": "propose", "to": CData.faction_index("rome"), "what": "team"})
		oc.set_plan(orders)
		await oc.flush_session()
		var r := await oc.submit(orders)
		if not r["ok"]:
			_err("submit turn %d: %s" % [t, r])
			await _wait_change(1.0)
			continue
		result["submissions"][str(t)] = orders
		_log("submitted turn %d (%d orders), all in: %s" % [t, orders.size(), r["data"].get("all_in", false)])


## Auto-resolve the battles that are only ours.
func _battles() -> bool:
	var did := false
	for b in oc.summary.get("battles", []):
		var bid := int(b["id"])
		var hs: Array = b["humans"]
		if not (hs.size() == 1 and int(hs[0]) == me) or oc.pending_upload(bid):
			continue
		var cr := await oc.claim(bid, "auto")
		if not cr["ok"]:
			continue
		var sb := CState.battle(oc.st, bid)
		if sb.is_empty():
			continue
		var built := CBattle.build(oc.st, sb, -1, 50)
		var sim := BattleSim.new()
		sim.setup(built["scenario"], int(built["seed"]))
		while sim.ended == 0 and sim.tick < 12000:
			sim.step()
		var outcome := CBattle.outcome_from_result(built, sim.result(), "auto")
		outcome["scale"] = 50
		await oc.upload_battle(bid, outcome)
		result["battles"] = int(result["battles"]) + 1
		did = true
	return did


func _wait_change(secs: float) -> void:
	var c0 := changes
	var end := Time.get_ticks_msec() + int(secs * 1000)
	while changes == c0 and Time.get_ticks_msec() < end:
		await create_timer(0.05).timeout


func _finish() -> void:
	if oc != null:
		await oc.sync()
		await oc.flush_session()
		result["final"] = {"version": oc.version, "hash": oc.state_hash, "local_hash": CState.hash_text(oc.st),
			"turn": int(oc.st.get("turn", -1)), "phase": str(oc.st.get("phase", "")), "outbox": oc.outbox.size(),
			"teams": oc.st.get("teams", []), "humans": oc.st.get("humans", []),
			"proposals": (oc.st.get("proposals", []) as Array).size()}
		var bad := 0
		for k in oc.verified:
			if int(oc.verified[k]) != 1:
				bad += 1
		result["verify_bad"] = bad
	result["id"] = cid
	result["ok"] = (result["errors"] as Array).is_empty()
	_write("result_%s.json" % role, JSON.stringify(result, "  "))
	_log("finished: %s" % ("OK" if result["ok"] else "ERRORS " + str(result["errors"])))
	quit(0 if result["ok"] else 1)


func _write(name: String, text: String) -> void:
	var f := FileAccess.open(dir.path_join(name), FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _wait_file(name: String, secs: float) -> String:
	var end := Time.get_ticks_msec() + int(secs * 1000)
	while Time.get_ticks_msec() < end:
		if FileAccess.file_exists(dir.path_join(name)):
			return FileAccess.get_file_as_string(dir.path_join(name)).strip_edges()
		await create_timer(0.1).timeout
	_err("no " + name)
	return ""
