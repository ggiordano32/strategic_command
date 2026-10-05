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

const CData := preload("res://campaign/cdata.gd")
const CState := preload("res://campaign/cstate.gd")
const CRules := preload("res://campaign/crules.gd")

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
