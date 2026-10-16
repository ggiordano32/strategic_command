extends SceneTree
## One captain of the online story end-to-end test (run by
## tests/story_online_e2e.py, which starts the Go server and two of these).
## The game's own online layer (game/net/) against the real server:
##
##   godot --headless --script res://tests/story_online_client.gd -- --server=URL
##     --role=A|B --dir=/tmp/x --hook=URL [--turns=6]
##
## A creates "The Brethren's Due" for two captains (the lead, the Brethren)
## and B joins as the second (the Miskito). Every story choice is a crew
## vote: both captains answer it through OnlineCampaign.answer_story (kind
## "story": CStory.answer run here, the state uploaded with the version it
## came from). The first vote is cast by both at the same moment (a file
## barrier: one upload wins, the other is re-applied on the newer state), and
## the two disagree on it (the heavier side carries it); later votes agree, B
## a moment after A (A sees "waiting for B"). Battles the story opens are
## fought by the formula by the lead. Writes <dir>/result_<role>.json.

const NetScript := preload("res://game/net/net.gd")
const OnlineCampaign := preload("res://game/net/online_campaign.gd")
const CData := preload("res://campaign/cdata.gd")
const CState := preload("res://campaign/cstate.gd")
const CTurn := preload("res://campaign/cturn.gd")
const CBattle := preload("res://campaign/cbattle.gd")
const CStory := preload("res://campaign/cstory.gd")
const SA := preload("res://game/campaign/story_autoplay.gd")

var role := "A"
var dir := ""
var hook := ""
var turns := 6
var me := 0
var net: NetScript
var oc: OnlineCampaign
var cid := ""
var changes := 0
var result := {"votes": [], "waited": 0, "battles": [], "errors": [], "notes": [], "submissions": {}, "conflicts": 0}
var t_start := 0
var _rng := RandomNumberGenerator.new()


func _initialize() -> void:
	_main.call_deferred()


func _log(s: String) -> void:
	print("[%s %5.1fs] %s" % [role, (Time.get_ticks_msec() - t_start) / 1000.0, s])


func _err(s: String) -> void:
	printerr("[%s] ERROR %s" % [role, s])
	(result["errors"] as Array).append(s)


func _main() -> void:
	t_start = Time.get_ticks_msec()
	_rng.seed = 77
	for a in OS.get_cmdline_user_args():
		var v: String = a.get_slice("=", 1)
		if a.begins_with("--role="):
			role = v
		elif a.begins_with("--dir="):
			dir = v
		elif a.begins_with("--hook="):
			hook = a.substr(7)
		elif a.begins_with("--turns="):
			turns = int(v)
	net = NetScript.new()
	net.accounts_path = dir.path_join("acc_" + role + ".json")
	root.add_child(net)
	await process_frame
	CData.use_pack("west")
	if role == "A":
		var st := CStory.new_story("Story E2E", 11, {"turn_timeout_h": 12}, "brethren", true)
		var lead := CStory.player(st)
		me = lead
		var r: Dictionary = await net.create_campaign(st, lead, {"webhook_url": hook, "discord_user": "111111111111111111"})
		if not r["ok"]:
			_err("create: %s" % r)
			await _finish()
			return
		cid = str(r["data"]["id"])
		_write("join.txt", str(r["data"]["join_code"]))
		_log("created %s as faction %d, join code %s" % [cid, lead, r["data"]["join_code"]])
	else:
		var code := await _wait_file("join.txt", 30.0)
		var typed := code.substr(0, 3).to_lower() + "-" + code.substr(3)
		var pv: Dictionary = await net.join_preview(typed)
		if not pv["ok"] or (pv["data"]["seats"] as Array).size() != 2:
			_err("join preview: %s" % pv)
			await _finish()
			return
		var seat := -1
		for sd in pv["data"]["seats"]:
			if not bool(sd.get("claimed", false)):
				seat = int(sd["f"])
		me = seat
		var r: Dictionary = await net.join(typed, seat, "222222222222222222")
		if not r["ok"]:
			_err("join: %s" % r)
			await _finish()
			return
		cid = str(r["data"]["id"])
		_log("joined %s as faction %d" % [cid, me])
	oc = net.open_campaign(cid)
	oc.cache_dir = dir.path_join("cache_" + role) + "/"
	oc.resolve_grace = 2.0
	oc.changed.connect(func(_w): changes += 1)
	oc.note.connect(func(t, k): (result["notes"] as Array).append("%s: %s" % [k, t]))
	oc.desync.connect(func(v, a, b): _err("desync at version %d: %s vs %s" % [v, a, b]))
	await oc.open()
	await _play()
	await _finish()


func _play() -> void:
	var guard := 0
	while guard < 6000:
		guard += 1
		await oc.sync()
		var st := oc.st
		var t := int(st["turn"])
		var ph := str(st["phase"])
		if ph == "over" or (t >= turns and ph == "plan" and not CStory.blocked(st)):
			_log("done at turn %d (%s)" % [t, ph])
			break
		if ph == "battles":
			if not await _battles():
				await _wait_change(1.5)
			continue
		if CStory.blocked(st):
			if not await _vote():
				await _wait_change(1.0)
			continue
		if oc.i_submitted():
			await _wait_change(1.5)
			continue
		var orders := SA.orders(st, me)
		oc.set_plan(orders)
		var r := await oc.submit(orders)
		if not r["ok"]:
			_err("submit turn %d: %s" % [t, r])
			await _wait_change(1.0)
			continue
		result["submissions"][str(t)] = orders
		_log("submitted turn %d (%d orders), all in: %s" % [t, orders.size(), r["data"].get("all_in", false)])


## Answer the story choice waiting for this seat (a vote). Returns whether
## anything was done.
func _vote() -> bool:
	var st := oc.st
	var mine := CStory.pending_for(st, me)
	if mine.is_empty():
		# We voted: the other captain is waited for.
		result["waited"] = int(result["waited"]) + 1
		return false
	var pe: Dictionary = mine[0]
	var pid := int(pe["id"])
	var n := (CStory.event_def(st, str(pe["e"]))["choices"] as Array).size()
	var allowed: Array = []
	for i in n:
		if CStory.answer_check(st, me, pid, i) == "":
			allowed.append(i)
	if allowed.is_empty():
		_err("no choice allowed for %s" % str(pe["e"]))
		return false
	var first := (result["votes"] as Array).is_empty()
	var k: int = int(allowed[0])
	if first and role == "B" and allowed.size() > 1:
		k = int(allowed[1])  # the disagreement
	if first:
		# Both captains answer the first choice at the same moment.
		_write("vote_%s" % role, "1")
		var other := "vote_%s" % ("B" if role == "A" else "A")
		for i in 200:
			if FileAccess.file_exists(dir.path_join(other)):
				break
			await create_timer(0.05).timeout
	elif role == "B":
		await create_timer(1.2).timeout  # A answers first and waits for B
		await oc.sync()
		if CStory.pending_for(oc.st, me).is_empty() or int(CStory.pending_for(oc.st, me)[0]["id"]) != pid:
			return true
	else:
		k = int(allowed[0])
	var base := oc.version
	var r := await oc.answer_story(pid, k)
	if not r["ok"]:
		_err("answer %s: %s" % [str(pe["e"]), r])
		return false
	if oc.version != base + 1:
		result["conflicts"] = int(result["conflicts"]) + 1
	(result["votes"] as Array).append({"e": str(pe["e"]), "pid": pid, "k": k, "turn": int(oc.st["turn"]), "from": base, "to": oc.version})
	_log("voted %d on %s (v%d -> v%d)" % [k, str(pe["e"]), base, oc.version])
	return true


## The lead fights the story's battles by the formula (the formula stands in for a fight).
func _battles() -> bool:
	if role != "A":
		return false
	var did := false
	for b in CTurn.pending_for(oc.st):
		var bid := int(b["id"])
		if oc.pending_upload(bid):
			continue
		var outcome := SA.outcome(oc.st, b, "random")
		var info := oc.battle_info(bid)
		if (info.get("humans", []) as Array).size() > 1 and int(info.get("command_by", -1)) != me:
			var rc := await oc.choose(bid, "command")  # both captains are in it: the lead takes command
			if not rc["ok"]:
				_err("command %d: %s" % [bid, rc])
				continue
		var cr := await oc.claim(bid, "auto")
		if not cr["ok"]:
			_log("claim %d refused: %s" % [bid, cr["error"]])
			continue
		var res := await oc.upload_battle(bid, outcome)
		(result["battles"] as Array).append({"id": bid, "res": res, "turn": int(oc.st["turn"])})
		_log("battle %d: %s" % [bid, res])
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
		if role == "B":
			var hist: Dictionary = await net.api.call_api("GET", "/api/c/%s/history" % cid, null, oc.token)
			var bad := 0
			var n := 0
			if hist["ok"]:
				for v in hist["data"]["versions"]:
					if str(v["kind"]) in ["turn", "battle", "story"]:
						oc.verified.erase(str(int(v["version"])))
						n += 1
						if not await oc.verify(int(v["version"])):
							bad += 1
			result["chain"] = {"checked": n, "bad": bad}
			_log("re-ran %d versions from their parents: %d mismatches" % [n, bad])
		await oc.flush_session()
		var slog: Array = CStory.S(oc.st)["log"] if CStory.on(oc.st) else []
		var votes_log: Array = []
		for e in slog:
			if e.has("v"):
				votes_log.append(e)
		result["final"] = {"version": oc.version, "hash": oc.state_hash, "local_hash": CState.hash_text(oc.st),
			"turn": int(oc.st.get("turn", -1)), "phase": str(oc.st.get("phase", "")), "outbox": oc.outbox.size(),
			"vote_log": votes_log, "pending": (CStory.S(oc.st)["pending"] as Array).size() if CStory.on(oc.st) else -1,
			"captains": CStory.captains(oc.st) if CStory.on(oc.st) else []}
	result["id"] = cid
	result["role"] = role
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
