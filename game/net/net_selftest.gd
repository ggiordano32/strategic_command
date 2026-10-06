extends Node
## Browser self-test of online play (testing aid; only runs with ?nettest=
## on the page URL). Drives the real online layer (Net, OnlineCampaign,
## HTTPRequest -> the browser's fetch; WebSocketPeer -> the browser's
## WebSocket) and prints "NETTEST ..." lines to the console, which
## server/cmd/webcheck reads:
##   ?nettest=a            create a campaign (Rome), print its join code, test
##                         the WebSocket echo, submit, wait (long-poll) for
##                         the turn to resolve, open the campaign screen
##   ?nettest=b&join=CODE  join it (Carthage), submit, resolve as the last
##                         submitter
##   ?nettest=ws&campaign=ID&token=T   only the WebSocket check
##   ?nettest=livea / ?nettest=liveb&join=CODE   a live co-op battle (milestone
##                         5): A creates a campaign with a battle of both
##                         armies and opens its room, B joins in the lobby;
##                         600 frames in lockstep with every frame's hash
##                         compared over the relay; then B leaves and joins
##                         again mid-battle (snapshot, catch-up) for 300 more

const CData := preload("res://campaign/cdata.gd")
const CState := preload("res://campaign/cstate.gd")
const CRules := preload("res://campaign/crules.gd")
const CBattle := preload("res://campaign/cbattle.gd")
const CoopSession := preload("res://game/net/coop_session.gd")

var role := ""
var params := {}
var _t0 := 0


func _log(s: String) -> void:
	print("NETTEST %s %s" % [role.to_upper(), s])


func _ready() -> void:
	_t0 = Time.get_ticks_msec()
	_log("START")
	_run.call_deferred()


func _run() -> void:
	var net := get_node("/root/Net")
	var ok: bool = await net.check_server()
	_log("SERVER %s %s" % ["OK" if ok else "DOWN", net.api.base_url])
	if not ok:
		return
	var rome := CData.faction_index("rome")
	var carth := CData.faction_index("carthage")
	if role == "livea" or role == "liveb":
		await _live(net, rome, carth)
		return
	if role == "ws":
		await _ws_check(net, str(params.get("campaign", "")), str(params.get("token", "")))
		return
	var cid := ""
	if role == "a":
		var st := CState.new_campaign("nettest", 3, [rome, carth], {"turn_timeout_h": 24})
		var r: Dictionary = await net.create_campaign(st, rome, {"invite": str(params.get("invite", ""))})
		if not r["ok"]:
			_log("FAIL create %s" % r)
			return
		cid = str(r["data"]["id"])
		_log("CODE %s ID %s" % [r["data"]["join_code"], cid])
		var e: Dictionary = net.accounts.get_entry(cid)
		await _ws_check(net, cid, str(e["token"]))
	else:
		var code := str(params.get("join", ""))
		var pv: Dictionary = await net.join_preview(code)
		if not pv["ok"]:
			_log("FAIL preview %s" % pv)
			return
		var r2: Dictionary = await net.join(code, carth)
		if not r2["ok"]:
			_log("FAIL join %s" % r2)
			return
		cid = str(r2["data"]["id"])
		_log("JOINED %s" % cid)
	var oc = net.open_campaign(cid)
	await oc.open()
	var f: int = oc.f
	# One real order: a building in the capital if it can be afforded.
	var orders: Array = []
	var cap := CData.region_index(str(CData.FACTIONS[f]["capital"]))
	var ps := CState.copy(oc.st)
	for c in [CData.FARM, CData.MARKET, CData.BARRACKS]:
		var o := {"t": "build", "r": cap, "chain": c}
		if CRules.apply_order(ps, f, o) == "":
			orders.append(o)
			break
	oc.set_plan(orders)
	await oc.flush_session()
	var t_sub := Time.get_ticks_msec()
	var r3: Dictionary = await oc.submit(orders)
	if not r3["ok"]:
		_log("FAIL submit %s" % r3)
		return
	_log("SUBMITTED all_in=%s" % r3["data"].get("all_in", false))
	# Wait for the turn to resolve (the long-poll brings the change).
	for i in 1200:
		if int(oc.st.get("turn", 0)) >= 1:
			break
		await get_tree().create_timer(0.1).timeout
	if int(oc.st.get("turn", 0)) < 1:
		_log("FAIL the turn did not resolve")
		return
	_log("DONE v%d %s turn %d waited_ms %d resolve %s" % [oc.version, oc.state_hash, int(oc.st["turn"]),
		Time.get_ticks_msec() - t_sub, oc.last_resolve.get("result", "-")])
	var hist: Dictionary = await net.api.call_api("GET", "/api/c/%s/history" % cid, null, oc.token)
	_log("HISTORY %d versions" % (hist["data"]["versions"] as Array).size() if hist["ok"] else "HISTORY FAIL")
	if role == "a":
		# Show the real campaign screen (for a screenshot).
		var main := get_tree().root.get_node_or_null("Main")
		if main == null:
			for c in get_tree().root.get_children():
				if c.has_method("_open_online"):
					main = c
		net.close_campaign()
		await get_tree().create_timer(0.5).timeout
		if main != null:
			main._open_online(cid)
			await get_tree().create_timer(3.0).timeout
			_log("SCREEN open")


## WebSocket echo through whatever proxy is in front of the server.
func _ws_check(net: Node, cid: String, token: String) -> void:
	var url: String = net.api.base_url.replace("https://", "wss://").replace("http://", "ws://") + "/api/c/%s/ws" % cid
	var ws := WebSocketPeer.new()
	var err := ws.connect_to_url(url)
	if err != OK:
		_log("WS FAIL connect error %d" % err)
		return
	var stage := 0
	var t_ping := 0
	var end := Time.get_ticks_msec() + 15000
	while Time.get_ticks_msec() < end:
		ws.poll()
		var state := ws.get_ready_state()
		if state == WebSocketPeer.STATE_OPEN and stage == 0:
			ws.send_text(JSON.stringify({"t": "auth", "token": token}))
			stage = 1
		while ws.get_available_packet_count() > 0:
			var msg = JSON.parse_string(ws.get_packet().get_string_from_utf8())
			if not (msg is Dictionary):
				continue
			if str(msg.get("t", "")) == "hello" and stage == 1:
				t_ping = Time.get_ticks_msec()
				ws.send_text(JSON.stringify({"t": "ping", "n": 42}))
				stage = 2
			elif str(msg.get("t", "")) == "pong" and stage == 2:
				_log("WS OK rtt_ms %d url %s" % [Time.get_ticks_msec() - t_ping, url])
				ws.close()
				return
		if state == WebSocketPeer.STATE_CLOSED:
			_log("WS FAIL closed %d %s (stage %d)" % [ws.get_close_code(), ws.get_close_reason(), stage])
			return
		await get_tree().process_frame
	_log("WS FAIL timeout (stage %d)" % stage)


## A campaign with live co-op battles to fight (tests): factions fa and fb
## each send an army of `units` units into each independent region of
## `regions`, both attacking, so every battle has both humans in it.
static func live_test_state(nm: String, sd: int, fa: int, fb: int, regions: Array, units: int = 4) -> Dictionary:
	var st := CState.new_campaign(nm, sd, [fa, fb], {"turn_timeout_h": 24})
	var src_a: Dictionary = CState.armies_of(st, fa)[0]
	var src_b: Dictionary = CState.armies_of(st, fb)[0]
	for r in regions:
		var aa := _clone_army(st, src_a, fa, int(r), units)
		var ab := _clone_army(st, src_b, fb, int(r), units)
		var b := CRules.start_battle(st, int(r), aa)
		(b["att"] as Array).append(int(ab["id"]))
		ab["busy"] = 1
	st["phase"] = "battles"
	return st


static func _clone_army(st: Dictionary, src: Dictionary, f: int, r: int, units: int) -> Dictionary:
	var a: Dictionary = src.duplicate(true)
	a["id"] = CRules.new_army_id(st, f)
	st["factions"][f]["next_army"] = int(st["factions"][f]["next_army"]) + 1
	a["r"] = r
	a["from"] = -1
	a["moved"] = 1
	a["busy"] = 0
	a["units"] = (a["units"] as Array).slice(0, units)
	(st["armies"] as Array).append(a)
	return a


# ------------------------------------------------------------ live battle ---

func _live(net: Node, rome: int, carth: int) -> void:
	var cid := ""
	if role == "livea":
		var st := live_test_state("livetest", 5, rome, carth, [7], 4)
		var r: Dictionary = await net.create_campaign(st, rome, {"invite": str(params.get("invite", ""))})
		if not r["ok"]:
			_log("FAIL create %s" % r)
			return
		cid = str(r["data"]["id"])
		_log("CODE %s ID %s" % [r["data"]["join_code"], cid])
	else:
		var r2: Dictionary = await net.join(str(params.get("join", "")), carth)
		if not r2["ok"]:
			_log("FAIL join %s" % r2)
			return
		cid = str(r2["data"]["id"])
		_log("JOINED %s" % cid)
	var oc = net.open_campaign(cid)
	await oc.open()
	var me: int = oc.f
	var bid := int((oc.st["battles"] as Array)[0]["id"])
	if role == "liveb":
		# Wait for A's room (the summary shows it live).
		for i in 300:
			await oc.sync()
			if oc.battle_info(bid).get("live") is Dictionary:
				break
			await get_tree().create_timer(0.2).timeout
	var s = _live_session(net, oc, bid, role == "livea")
	var t0 := Time.get_ticks_msec()
	var target := 600
	var rejoined := false
	while Time.get_ticks_msec() - t0 < 240000:
		await get_tree().process_frame
		if s.phase == "gone":
			_log("FAIL session gone")
			return
		if s.ls == null:
			continue
		if role == "liveb" and not rejoined and s.ls.frame >= target:
			_log("LIVE frames %d checks %d desyncs %d rtt_ms %d waits %d wait_ms_max %d" % [s.ls.frame, s.stats["hash_checks"],
				s.stats["desyncs"], int(s.room.srtt_ms), s.stats["waits"], int(s.stats["wait_ms_max"])])
			s.leave()
			await get_tree().create_timer(2.0).timeout
			s.queue_free()
			s = _live_session(net, oc, bid, false)
			rejoined = true
			var t1 := Time.get_ticks_msec()
			while s.ls == null or not s.ls.is_active(me) or s.catching_up:
				await get_tree().process_frame
				if Time.get_ticks_msec() - t1 > 60000:
					_log("FAIL rejoin timed out (phase %s)" % s.phase)
					return
			_log("REJOIN frame %d snapshot_bytes %d restore_ms %.1f catchup_frames %d catchup_ms %d join_ms %d" % [s.ls.frame,
				int(s.stats.get("snap_rx_bytes", 0)),
				float(s.stats["restore_ms"]), int(s.stats["catchup_frames"]), int(s.stats["catchup_ms"]), Time.get_ticks_msec() - t1])
			target = s.ls.frame + 300
			continue
		if (role == "liveb" and rejoined or role == "livea") and s.ls.frame >= target and s.stats["hash_checks"] > 250:
			if role == "liveb" or s.ls.frame >= 950:
				break
	if s.ls == null:
		_log("FAIL no battle")
		return
	_log("DONE frames %d tick %d checks %d desyncs %d hash %08x rtt_ms %d" % [s.ls.frame, s.ls.sim.tick, s.stats["hash_checks"],
		s.stats["desyncs"], s.ls.state_hash(), int(s.room.srtt_ms)])
	await get_tree().create_timer(3.0).timeout
	s.leave()


func _live_session(net: Node, oc, bid: int, create: bool):
	var b := CState.battle(oc.st, bid)
	var hs: Array = CRules.battle_humans(oc.st, b)
	var built := CBattle.build(oc.st, b, int(hs.min()))
	var s = CoopSession.new()
	add_child(s)
	s.setup(net.api.base_url, oc.id, oc.token, oc.f, built, hs, oc.version, create)
	s.frame_sec = 0.025
	s.hash_every = 1
	s.note.connect(func(t: String, k: String): _log("NOTE %s %s" % [k, t]))
	s.failed.connect(func(c: String, t: String): _log("FAIL room %s %s" % [c, t]))
	return s
