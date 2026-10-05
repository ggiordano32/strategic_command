extends SceneTree
## One player of the online end-to-end test (run by tests/online_e2e.py,
## which starts the Go server, a fake Discord webhook and two of these).
## Uses the game's own online layer (game/net/) against the real server:
##
##   godot --headless --script res://tests/online_client.gd -- --server=URL
##     --role=A|B --dir=/tmp/x --hook=URL [--turns=9 --race-turn=2
##     --link-turn=3 --offline-turn=5]
##
## A (Rome) creates the campaign and B (Carthage) joins with the code. Both
## plan with tests/online_policy.gd and submit; the last submitter resolves.
## Special turns: race-turn: both clients resolve and upload at the same
## moment (a file barrier); link-turn: A saves half a plan, makes a device
## code, and a second "device" (its own accounts file and cache) claims it,
## finds the half plan in the session, completes and submits it;
## offline-turn: A goes away (stops its client); B submits, moves the
## server clock past the 12 h deadline and forces the turn, then takes
## command of A's battles; A comes back and verifies B's results.
## Battles are auto-resolved with the battle sim (half-size units) by the
## client whose army is in them (Rome takes command when both are); the
## first battle upload of each client hits a simulated network failure
## (A: fails before sending; B: the answer is lost after the server
## committed). Writes <dir>/result_<role>.json; exit code 0 on success.

const NetScript := preload("res://game/net/net.gd")
const OnlineCampaign := preload("res://game/net/online_campaign.gd")
const Policy := preload("res://tests/online_policy.gd")
const CData := preload("res://campaign/cdata.gd")
const CState := preload("res://campaign/cstate.gd")
const CTurn := preload("res://campaign/cturn.gd")
const CBattle := preload("res://campaign/cbattle.gd")
const BattleSim := preload("res://sim/battle_sim.gd")

var role := "A"
var dir := ""
var hook := ""
var turns := 9
var race_turn := 2
var link_turn := 3
var offline_turn := 5
var fa := 0
var fb := 1
var me := 0
var net: NetScript
var oc: OnlineCampaign
var cid := ""
var changes := 0
var result := {"submissions": {}, "battles": [], "errors": [], "notes": [], "race": {}, "verify_ok": 0, "verify_bad": 0,
	"device_switch": {}, "forced": "", "upload_failures": []}
var failed_first_upload := false
var t_start := 0
var own_battles := {}   ## A: battle id -> true (handle) / false (delegated to B)
const ATTACK_PCT := 110


func _initialize() -> void:
	_main.call_deferred()


func _log(s: String) -> void:
	print("[%s %5.1fs] %s" % [role, (Time.get_ticks_msec() - t_start) / 1000.0, s])


func _err(s: String) -> void:
	printerr("[%s] ERROR %s" % [role, s])
	(result["errors"] as Array).append(s)


func _main() -> void:
	t_start = Time.get_ticks_msec()
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
		elif a.begins_with("--race-turn="):
			race_turn = int(v)
		elif a.begins_with("--link-turn="):
			link_turn = int(v)
		elif a.begins_with("--offline-turn="):
			offline_turn = int(v)
	fa = CData.faction_index("rome")
	fb = CData.faction_index("carthage")
	me = fa if role == "A" else fb
	net = _new_net("acc_" + role)
	await process_frame
	if role == "A":
		var st := CState.new_campaign("E2E", 11, [fa, fb], {"turn_timeout_h": 12})
		var r: Dictionary = await net.create_campaign(st, fa, {"webhook_url": hook, "discord_user": "111111111111111111"})
		if not r["ok"]:
			_err("create: %s" % r)
			await _finish()
			return
		cid = str(r["data"]["id"])
		_write("join.txt", str(r["data"]["join_code"]))
		_log("created %s, join code %s" % [cid, r["data"]["join_code"]])
	else:
		var code := await _wait_file("join.txt", 30.0)
		# Typed on a phone: lower case with a dash.
		var typed := code.substr(0, 3).to_lower() + "-" + code.substr(3)
		var pv: Dictionary = await net.join_preview(typed)
		if not pv["ok"] or (pv["data"]["seats"] as Array).size() != 2:
			_err("join preview: %s" % pv)
			await _finish()
			return
		var r: Dictionary = await net.join(typed, fb, "222222222222222222")
		if not r["ok"]:
			_err("join: %s" % r)
			await _finish()
			return
		cid = str(r["data"]["id"])
		_log("joined %s" % cid)
	oc = _open(net, "cache_" + role)
	await oc.open()
	await _play()
	await _finish()


func _new_net(acc: String) -> NetScript:
	var n := NetScript.new()
	n.accounts_path = dir.path_join(acc + ".json")
	root.add_child(n)
	return n


func _open(n: NetScript, cache: String) -> OnlineCampaign:
	var c := n.open_campaign(cid)
	c.cache_dir = dir.path_join(cache) + "/"
	c.resolve_grace = 3.0
	c.changed.connect(func(_w): changes += 1)
	c.note.connect(func(t, k): (result["notes"] as Array).append("%s: %s" % [k, t]); _log("note (%s): %s" % [k, t]))
	c.desync.connect(func(v, a, b): _err("desync at version %d: %s vs %s" % [v, a, b]))
	return c


func _play() -> void:
	var did_offline := false
	var guard := 0
	while guard < 20000:
		guard += 1
		await oc.sync()
		var st := oc.st
		var t := int(st["turn"])
		var ph := str(st["phase"])
		if ph == "over" or (t >= turns and ph == "plan"):
			_log("done at turn %d (%s)" % [t, ph])
			break
		if role == "A" and t == offline_turn and not did_offline and ph == "plan":
			did_offline = true
			await _go_offline()
			continue
		if ph == "battles":
			if not await _battles():
				await _wait_change(2.0)
			continue
		if oc.i_submitted():
			await _wait_change(2.0)
			continue
		if t == race_turn:
			oc.resolve_barrier = _barrier.bind(t)
			oc.resolve_grace = 0.0
		else:
			oc.resolve_barrier = Callable()
			oc.resolve_grace = 3.0
		if role == "A" and t == link_turn:
			await _device_switch(t)
			continue
		var orders := Policy.plan(st, me, ATTACK_PCT, true)
		oc.set_plan(orders)
		await oc.flush_session()
		var r := await oc.submit(orders)
		if not r["ok"]:
			_err("submit turn %d: %s" % [t, r])
			await _wait_change(1.0)
			continue
		result["submissions"][str(t)] = orders
		_log("submitted turn %d (%d orders), all in: %s" % [t, orders.size(), r["data"].get("all_in", false)])
		if t == race_turn:
			await _wait_turn_past(t)
			result["race"] = oc.last_resolve.duplicate()
			_log("race turn %d: %s" % [t, oc.last_resolve])
		if role == "B" and t == offline_turn:
			await _force_turn(t)


func _wait_change(secs: float) -> void:
	var c0 := changes
	var end := Time.get_ticks_msec() + int(secs * 1000)
	while changes == c0 and Time.get_ticks_msec() < end:
		await create_timer(0.05).timeout


func _wait_turn_past(t: int) -> void:
	for i in 600:
		if int(oc.st["turn"]) > t:
			return
		await _wait_change(0.5)
	_err("turn %d did not resolve" % t)


func _barrier(t: int) -> void:
	_write("race_%d_%s" % [t, role], "1")
	var other := "race_%d_%s" % [t, "B" if role == "A" else "A"]
	for i in 400:
		if FileAccess.file_exists(dir.path_join(other)):
			return
		await create_timer(0.025).timeout
	_log("race barrier: the other client never came (no race this turn)")


# ------------------------------------------------------------- battles ---

## Resolve the pending battles this client is responsible for; returns
## whether it did anything.
func _battles() -> bool:
	var did := false
	var ally_away := FileAccess.file_exists(dir.path_join("A_offline"))
	for b in oc.summary.get("battles", []):
		var bid := int(b["id"])
		var hs: Array = b["humans"]
		var mine := false
		var need_cmd := false
		if hs.size() == 1 and int(hs[0]) == me:
			mine = true
			if role == "A":
				# Every second battle of Rome's is left to Carthage, who takes
				# command of Rome's army there.
				if not own_battles.has(bid):
					var n := own_battles.size()
					own_battles[bid] = n % 2 == 0
					if n % 2 == 1:
						_write("delegate_%d" % bid, "1")
						_log("leaving battle %d to the ally" % bid)
				mine = bool(own_battles[bid])
		elif hs.size() == 1 and role == "B" and FileAccess.file_exists(dir.path_join("delegate_%d" % bid)):
			mine = true
			need_cmd = true
		elif hs.size() > 1:
			mine = me == fa or ally_away
			need_cmd = true
		elif role == "B" and ally_away:
			mine = true
			need_cmd = true
		if not mine or oc.pending_upload(bid):
			continue
		var claim = b.get("claim")
		if claim is Dictionary and not bool(claim.get("mine", false)):
			continue
		if need_cmd and int(b.get("command_by", -1)) != me:
			var rc := await oc.choose(bid, "command")
			if not rc["ok"]:
				_err("command %d: %s" % [bid, rc])
				continue
			_log("took command in battle %d" % bid)
		var cr := await oc.claim(bid, "auto")
		if not cr["ok"]:
			_log("claim %d refused: %s" % [bid, cr["error"]])
			continue
		var sb := CState.battle(oc.st, bid)
		if sb.is_empty():
			continue
		var t0 := Time.get_ticks_msec()
		var built := CBattle.build(oc.st, sb, -1, 50)
		var sim := BattleSim.new()
		sim.setup(built["scenario"], int(built["seed"]))
		while sim.ended == 0 and sim.tick < 12000:
			sim.step()
		var outcome := CBattle.outcome_from_result(built, sim.result(), "auto")
		outcome["scale"] = 50
		var sim_ms := Time.get_ticks_msec() - t0
		var fault := ""
		if not failed_first_upload:
			failed_first_upload = true
			# More failures than the HTTP retries absorb, so the outbox has to
			# keep the result: A's never reach the server and A then closes
			# the page; B's reach it but every answer is lost.
			if role == "A":
				net.api.debug_fail["POST:/state"] = 3
				fault = "fail_then_page_closed"
			else:
				net.api.debug_drop["POST:/state"] = 3
				fault = "answers_lost"
		var res := await oc.upload_battle(bid, outcome)
		if fault == "fail_then_page_closed":
			var kept := oc.pending_upload(bid)
			oc.close()
			net.close_campaign()
			oc = _open(net, "cache_" + role)
			await oc.open()  # the reopened page finds the result in its cache and sends it
			for i in 400:
				if not oc.pending_upload(bid):
					break
				await create_timer(0.1).timeout
			(result["upload_failures"] as Array).append({"battle": bid, "fault": fault, "first": res,
				"kept_in_outbox": kept, "recovered": not oc.pending_upload(bid) and CState.battle(oc.st, bid).is_empty()})
		elif fault != "":
			for i in 400:
				if not oc.pending_upload(bid):
					break
				await create_timer(0.1).timeout
			(result["upload_failures"] as Array).append({"battle": bid, "fault": fault, "first": res,
				"recovered": not oc.pending_upload(bid) and CState.battle(oc.st, bid).is_empty()})
		result["battles"].append({"id": bid, "region": int(b["r"]), "turn": int(oc.st["turn"]), "res": res,
			"winner": int(outcome["winner"]), "sim_ms": sim_ms, "command": need_cmd})
		_log("battle %d at %s: %s (sim %d ms%s)" % [bid, b.get("region", ""), res, sim_ms, ", " + fault if fault != "" else ""])
		did = true
	return did


# ------------------------------------------------------- device switch ---

func _device_switch(t: int) -> void:
	var orders := Policy.plan(oc.st, me, ATTACK_PCT, true)
	var half := orders.slice(0, maxi(1, orders.size() / 2))
	oc.set_plan(half)
	await oc.flush_session()
	var link := await oc.make_link()
	if not link["ok"]:
		_err("make link: %s" % link)
		return
	var code := str(link["data"]["code"])
	_log("device code %s; switching to the second device" % code)
	var net2 := _new_net("acc_A2")
	await process_frame
	var cl: Dictionary = await net2.claim_link(code.to_lower())
	if not cl["ok"]:
		_err("claim link: %s" % cl)
		return
	var oc2 := _open(net2, "cache_A2")
	await oc2.open()
	var got := oc2.plan_orders()
	var same_half := JSON.stringify(got) == JSON.stringify(CState.normalise(half))
	if not same_half:
		_err("the half plan did not reach the second device: %s vs %s" % [got, half])
	var full := Policy.plan(oc2.st, me, ATTACK_PCT, true)
	oc2.set_plan(full)
	var r := await oc2.submit(full)
	if not r["ok"]:
		_err("submit from the second device: %s" % r)
	result["submissions"][str(t)] = full
	result["device_switch"] = {"turn": t, "half_plan_found": same_half, "half": half.size(), "full": full.size(),
		"submitted": r["ok"], "same_as_first_device": JSON.stringify(full) == JSON.stringify(orders)}
	_log("second device submitted turn %d (%d orders; the half plan of %d was there: %s)" % [t, full.size(), half.size(), same_half])
	await oc2.flush_session()
	oc2.close()
	# Back on the first device: it sees the submission.
	for i in 100:
		await oc.sync()
		if oc.i_submitted() or int(oc.st["turn"]) > t:
			break
		await create_timer(0.1).timeout


# ------------------------------------------------------- offline turn ---

func _go_offline() -> void:
	var t := int(oc.st["turn"])
	_write("A_offline", "1")
	_log("going offline for turn %d" % t)
	oc.close()
	net.close_campaign()
	# Watch the server without the client (someone glancing at Discord).
	var e := net.accounts.get_entry(cid)
	while true:
		await create_timer(1.0).timeout
		var r: Dictionary = await net.api.call_api("GET", "/api/c/%s" % cid, null, str(e["token"]))
		if r["ok"] and int(r["data"]["turn"]) > t and str(r["data"]["phase"]) != "battles":
			break
	DirAccess.remove_absolute(dir.path_join("A_offline"))
	_log("back online")
	oc = _open(net, "cache_" + role)
	await oc.open()
	# The versions made while away were made by B: check the latest here.
	for i in 50:
		if oc.verified.has(str(oc.version)):
			break
		await create_timer(0.1).timeout


func _force_turn(t: int) -> void:
	var advanced := false
	for i in 600:
		await oc.sync()
		if int(oc.st["turn"]) > t:
			break
		if not advanced and not bool(oc.summary.get("all_in", false)) and int(oc.summary.get("deadline", 0)) > 0:
			# 10 h on (the 2-hour warning), then past the 12 h deadline.
			var r: Dictionary = await net.api.call_api("POST", "/api/test/clock", {"advance_ms": 10 * 3600000 + 60000})
			await create_timer(0.3).timeout
			r = await net.api.call_api("POST", "/api/test/clock", {"advance_ms": 2 * 3600000})
			advanced = r["ok"]
			_log("moved the server clock past the deadline")
			await oc.sync()
		if bool(oc.summary.get("deadline_expired", false)):
			var res := await oc.resolve_now(true)
			result["forced"] = res
			_log("forced turn %d: %s" % [t, res])
			if res == "ok":
				break
		await _wait_change(0.5)


# ----------------------------------------------------------------- end ---

func _finish() -> void:
	if oc != null:
		await oc.sync()
		# B re-runs every step of the whole history (the full chain check).
		if role == "B":
			var hist: Dictionary = await net.api.call_api("GET", "/api/c/%s/history" % cid, null, oc.token)
			var bad := 0
			var n := 0
			if hist["ok"]:
				for v in hist["data"]["versions"]:
					if str(v["kind"]) in ["turn", "battle"]:
						oc.verified.erase(str(int(v["version"])))
						n += 1
						if not await oc.verify(int(v["version"])):
							bad += 1
			result["chain"] = {"checked": n, "bad": bad}
			_log("re-ran %d versions from their parents: %d mismatches" % [n, bad])
		for k in oc.verified:
			if int(oc.verified[k]) == 1:
				result["verify_ok"] = int(result["verify_ok"]) + 1
			else:
				result["verify_bad"] = int(result["verify_bad"]) + 1
		await oc.flush_session()
		result["final"] = {"version": oc.version, "hash": oc.state_hash, "local_hash": CState.hash_text(oc.st),
			"turn": int(oc.st.get("turn", -1)), "phase": str(oc.st.get("phase", "")), "outbox": oc.outbox.size()}
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
