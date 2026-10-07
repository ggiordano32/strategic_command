extends Node
## WebSocket connection to one live battle room on the campaign server
## (docs/SERVER.md "Live battle rooms"). Connects, authenticates with the
## seat token, enters the room, and from then on passes every message on
## (signal `message`) and sends what it is given (JSON text frames). Pings
## every second to measure the round trip (smoothed `srtt_ms` / `rttvar_ms`)
## and to keep the server from closing a quiet connection; a connection
## that hears nothing for 6 s is treated as dead. Reconnects by itself with
## backoff (1 s doubling to 8 s) until close() - the caller learns about it
## through `state_changed` and the next "room" reply, and decides how to
## catch up (replay or snapshot). On the web WebSocketPeer is the
## browser's WebSocket.

signal message(m: Dictionary)
signal state_changed(state: String)          ## connecting, open, retrying, closed
signal failed(code: String, text: String)    ## the room refused us (no retry)

const PING_SEC := 1.0
const DEAD_SEC := 6.0
## Room errors that will not change by retrying.
const FATAL := ["no_room", "not_in_battle", "not_pending", "stale", "claimed", "unauthorized", "bad_code"]

var url := ""
var token := ""
var room_body: Dictionary = {}
var state := "idle"
var srtt_ms := -1.0
var rttvar_ms := 0.0
var last_rtt_ms := -1.0
var reconnects := 0
var sent := 0
var received := 0
var sent_bytes := 0
var received_bytes := 0

var _ws: WebSocketPeer = null
var _stage := 0          ## 0 socket, 1 waiting hello, 2 waiting room reply, 3 in room
var _ping_n := 0
var _pings := {}         ## n -> msec sent
var _ping_t := 0.0
var _last_recv := 0
var _retry_in := -1.0
var _backoff := 1.0
var _closing := false


## base: "http(s)://host[:port]"; room: the {"t":"room", ...} body.
func start(base: String, cid: String, p_token: String, room: Dictionary) -> void:
	start_url(base.replace("https://", "wss://").replace("http://", "ws://") + "/api/c/%s/ws" % cid, p_token, room)


## The same with the WebSocket URL given (custom battle rooms).
func start_url(ws_url: String, p_token: String, room: Dictionary) -> void:
	url = ws_url
	token = p_token
	room_body = room.duplicate()
	room_body["t"] = "room"
	_closing = false
	_connect()


func _connect() -> void:
	_ws = WebSocketPeer.new()
	_ws.inbound_buffer_size = 4 << 20
	_ws.outbound_buffer_size = 4 << 20
	_ws.max_queued_packets = 8192
	_stage = 0
	_pings.clear()
	var err := _ws.connect_to_url(url)
	if err != OK:
		_schedule_retry()
		return
	_last_recv = Time.get_ticks_msec()
	_set_state("connecting")


func _set_state(s: String) -> void:
	if s != state:
		state = s
		state_changed.emit(s)


func is_open() -> bool:
	return _stage == 3 and _ws != null and _ws.get_ready_state() == WebSocketPeer.STATE_OPEN


## Send a message (only once in the room). Returns false if not connected.
func send(d: Dictionary) -> bool:
	if not is_open():
		return false
	return _send_raw(d)


func _send_raw(d: Dictionary) -> bool:
	var text := JSON.stringify(d)
	if _ws.send_text(text) != OK:
		return false
	sent += 1
	sent_bytes += text.length()
	return true


## Close for good (no reconnect).
func close() -> void:
	_closing = true
	if _ws != null and _ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_ws.close(1000, "bye")
	_set_state("closed")


func _schedule_retry() -> void:
	if _closing:
		_set_state("closed")
		return
	_stage = 0
	_retry_in = _backoff * randf_range(0.8, 1.2)
	_backoff = minf(_backoff * 2.0, 8.0)
	_set_state("retrying")


func _process(delta: float) -> void:
	poll(delta)


## Poll the socket (called every frame; tests may call it directly).
func poll(delta: float = 0.0) -> void:
	if _retry_in >= 0.0:
		_retry_in -= delta
		if _retry_in < 0.0 and not _closing:
			reconnects += 1
			_connect()
		return
	if _ws == null:
		return
	_ws.poll()
	var st := _ws.get_ready_state()
	if st == WebSocketPeer.STATE_CLOSED:
		_ws = null
		if not _closing:
			_schedule_retry()
		return
	if st != WebSocketPeer.STATE_OPEN:
		return
	if _stage == 0:
		_send_raw({"t": "auth", "token": token})
		_stage = 1
	while _ws != null and _ws.get_available_packet_count() > 0:
		var pkt := _ws.get_packet()
		received += 1
		received_bytes += pkt.size()
		_last_recv = Time.get_ticks_msec()
		var m = JSON.parse_string(pkt.get_string_from_utf8())
		if m is Dictionary:
			_on_message(m)
	if _ws == null:
		return
	if _stage >= 2:
		_ping_t -= delta
		if _ping_t <= 0.0:
			_ping_t = PING_SEC
			_ping_n += 1
			_pings[_ping_n] = Time.get_ticks_msec()
			_send_raw({"t": "ping", "n": _ping_n})
			if _pings.size() > 20:
				_pings.erase(_pings.keys().min())
	if Time.get_ticks_msec() - _last_recv > int(DEAD_SEC * 1000.0):
		# Heard nothing (not even pongs): the connection is dead.
		_ws.close()
		_ws = null
		_schedule_retry()


func _on_message(m: Dictionary) -> void:
	var t := str(m.get("t", ""))
	if t == "pong":
		var n := int(m.get("n", -1))
		if _pings.has(n):
			var r := float(Time.get_ticks_msec() - int(_pings[n]))
			_pings.erase(n)
			last_rtt_ms = r
			if srtt_ms < 0.0:
				srtt_ms = r
				rttvar_ms = r / 2.0
			else:
				rttvar_ms = 0.75 * rttvar_ms + 0.25 * absf(srtt_ms - r)
				srtt_ms = 0.875 * srtt_ms + 0.125 * r
		return
	if _stage == 1 and t == "hello":
		_stage = 2
		_send_raw(room_body)
		return
	if _stage == 2:
		if t == "room":
			_stage = 3
			_backoff = 1.0
			_set_state("open")
			message.emit(m)
		elif t == "error":
			var code := str(m.get("code", ""))
			if code in FATAL:
				_closing = true
				failed.emit(code, str(m.get("message", "")))
				_ws.close()
				_set_state("closed")
			else:
				_ws.close()
		return
	message.emit(m)
