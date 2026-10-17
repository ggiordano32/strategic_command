extends Node
## HTTP client for the campaign server (docs/SERVER.md). One HTTPRequest
## node per call, so calls run side by side and never block the UI; every
## call has a timeout; idempotent calls are retried on network errors, 429
## and 5xx with exponential backoff and jitter.
##
##   var r: Dictionary = await api.call_api("GET", "/api/c/%s" % id, null, token)
##   r = {ok, status, data, error (server error code or "network"),
##        message, network (true when the server was not reached)}
##
## The server is chosen in this order (`pick_base_url`): "--server=URL" on the
## command line, the address saved on this device (accounts.json "server"),
## the page's own origin on the web when that origin is a game server (Net
## probes /api/info for that), else OFFICIAL_SERVER. `base_url` is "" only in
## tests that build an Api by hand; every call then fails at once with error
## "no_server".

signal reachability_changed(online: bool)

const DEFAULT_TIMEOUT := 15.0
const MAX_BACKOFF := 30.0
const OFFICIAL_SERVER := "https://strategiccommand.ggior32.dev"

var base_url := ""
var online := true            # last call reached the server
var last_error := ""
var calls := 0
var failures := 0

## Testing aids: "METHOD:/path/suffix" -> how many times to fail. "fail"
## fails the call before it is sent; "drop" sends it and then pretends the
## answer was lost (as when the connection drops after the server committed).
var debug_fail := {}
var debug_drop := {}


func _ready() -> void:
	if base_url == "":
		base_url = detect_base_url()


## The server address to start with: --server=, then `saved`, then the page
## origin when `origin_is_server`, else the official server. Pure: tests call
## it with made-up arguments.
static func pick_base_url(arg: String, saved: String, origin: String = "", origin_is_server: bool = false) -> String:
	var u := normalise_url(arg)
	if u != "":
		return u
	u = normalise_url(saved)
	if u != "":
		return u
	if origin_is_server and origin != "":
		return normalise_url(origin)
	return OFFICIAL_SERVER


## The command line and the saved address (the page origin is probed later,
## see Net.check_server).
static func detect_base_url(saved: String = "") -> String:
	var arg := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--server="):
			arg = a.get_slice("=", 1)
	return pick_base_url(arg, saved)


## "Host:8060/" -> "http://host:8060" (no scheme: http for a bare IP, a
## localhost name or a port, else https); only scheme://host[:port] is kept
## (no path, query or trailing slash). "" when it is not an address.
static func normalise_url(s: String) -> String:
	var t := s.strip_edges()
	if t == "":
		return ""
	var scheme := ""
	if t.contains("://"):
		scheme = t.get_slice("://", 0).to_lower()
		t = t.substr(t.find("://") + 3)
		if scheme != "http" and scheme != "https":
			return ""
	for sep in ["/", "?", "#"]:
		t = t.get_slice(sep, 0)
	t = t.strip_edges().to_lower()
	if t == "" or t.contains(" ") or t.contains("@"):
		return ""
	if scheme == "":
		var host := t.get_slice(":", 0)
		var local := t.contains(":") or host == "localhost" or host.is_valid_ip_address() or not host.contains(".")
		scheme = "http" if local else "https"
	return scheme + "://" + t


## Make one API call. body: Dictionary / Array (sent as JSON) or null.
## opts: {base: another server's address (default: base_url), timeout: s, retries: n (default 2 for GET, 0 otherwise),
## retry_on_status: bool (429 / 5xx, default true when retries > 0)}.
func call_api(method: String, path: String, body = null, token: String = "", opts: Dictionary = {}) -> Dictionary:
	var base: String = str(opts.get("base", base_url))
	if base == "":
		return {"ok": false, "status": 0, "data": {}, "error": "no_server", "message": "No game server.", "network": true}
	var retries: int = int(opts.get("retries", 2 if method == "GET" else 0))
	var backoff := 0.6
	var res := {}
	for attempt in retries + 1:
		res = await _once(method, path, body, token, float(opts.get("timeout", DEFAULT_TIMEOUT)), base)
		var transient: bool = res["network"] or int(res["status"]) == 429 or int(res["status"]) >= 500
		if not transient or attempt == retries:
			break
		var wait := minf(backoff, MAX_BACKOFF) * randf_range(0.8, 1.25)
		await get_tree().create_timer(wait).timeout
		backoff *= 2.0
	return res


func _debug_hit(table: Dictionary, method: String, path: String) -> bool:
	var p := path.get_slice("?", 0)
	for k in table.keys():
		var key := str(k)
		if key.get_slice(":", 0) == method and p.ends_with(key.get_slice(":", 1)) and int(table[k]) > 0:
			table[k] = int(table[k]) - 1
			return true
	return false


func _once(method: String, path: String, body, token: String, timeout: float, base: String) -> Dictionary:
	calls += 1
	var quiet := base != base_url  # a test call to another server says nothing about this one
	if _debug_hit(debug_fail, method, path):
		await get_tree().process_frame
		return _failed("network", "simulated network failure", 0, quiet)
	var req := HTTPRequest.new()
	req.timeout = timeout
	# On the web the browser's fetch already decompresses gzip answers (and
	# keeps the Content-Encoding header), so HTTPRequest must not try again.
	req.accept_gzip = not OS.has_feature("web")
	req.use_threads = false
	add_child(req)
	var headers := PackedStringArray(["Accept: application/json"])
	if token != "":
		headers.append("Authorization: Bearer " + token)
	var text := ""
	if body != null:
		headers.append("Content-Type: application/json")
		text = JSON.stringify(body)
	var m := HTTPClient.METHOD_GET
	match method:
		"POST":
			m = HTTPClient.METHOD_POST
		"PUT":
			m = HTTPClient.METHOD_PUT
		"DELETE":
			m = HTTPClient.METHOD_DELETE
	var err := req.request(base + path, headers, m, text)
	if err != OK:
		req.queue_free()
		return _failed("network", "request could not start (%d)" % err, 0, quiet)
	var out: Array = await req.request_completed
	req.queue_free()
	var result: int = out[0]
	var code: int = out[1]
	var raw: PackedByteArray = out[3]
	if _debug_hit(debug_drop, method, path):
		return _failed("network", "simulated lost answer", 0, quiet)
	if result != HTTPRequest.RESULT_SUCCESS:
		var why := "timeout" if result == HTTPRequest.RESULT_TIMEOUT else "network error %d" % result
		return _failed("network", why, 0, quiet)
	if not quiet:
		_set_online(true)
	var data = {}
	var answer := raw.get_string_from_utf8() if raw.size() > 0 else ""
	if answer.begins_with("{") or answer.begins_with("["):  # not an HTML error page
		var parsed = JSON.parse_string(answer)
		if parsed != null:
			data = parsed
	if code >= 200 and code < 300:
		return {"ok": true, "status": code, "data": data, "error": "", "message": "", "network": false}
	var ecode := "http_%d" % code
	var msg := ""
	if data is Dictionary:
		ecode = str(data.get("error", ecode))
		msg = str(data.get("message", ""))
	failures += 1
	last_error = "%s: %s" % [ecode, msg]
	return {"ok": false, "status": code, "data": data, "error": ecode, "message": msg, "network": false}


func _failed(ecode: String, msg: String, code: int, quiet: bool = false) -> Dictionary:
	if not quiet:
		failures += 1
		last_error = msg
		_set_online(false)
	return {"ok": false, "status": code, "data": {}, "error": ecode, "message": msg, "network": true}


func _set_online(v: bool) -> void:
	if v != online:
		online = v
		reachability_changed.emit(v)
