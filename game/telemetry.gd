extends Node
## Playtest telemetry (autoload "Telemetry"). View layer only: it never reads
## or writes anything the sim uses, so it cannot affect sim state or hashes.
##
## Active on web builds, where it posts to <page origin>/telemetry (served by
## tools/serve_web.py). On native builds it is off unless started with
## "-- --telemetry-url=http://host:port/telemetry".
##
## Records are queued and sent in batches every FLUSH_SEC with HTTPRequest
## (one request in flight at most). When the page is hidden or closed, the
## queue is sent with navigator.sendBeacon. Failures are silent; after a few
## consecutive failures telemetry switches itself off for the page load.
##
## Every record: {"session", "seq", "kind", "t" (ms since page load), ...}.

signal page_hiding  ## emitted just before the page-hide beacon is sent

const FLUSH_SEC := 5.0
const MAX_QUEUE := 600
const MAX_FAILURES := 3

var enabled := false
var session_id := ""
var build_stamp := "dev"

var _url := ""
var _seq := 0
var _queue: Array = []
var _http: HTTPRequest
var _in_flight := false
var _failures := 0
var _flush_timer := 0.0
var _js_tele: JavaScriptObject = null
var _js_hide_cb: JavaScriptObject = null

const JS_HOOKS := """
(function () {
	if (window.__scTele) return;
	var T = window.__scTele = { events: [], onHide: null };
	function push(kind, data) {
		data = data || {};
		data.kind = kind;
		data.t_js = Math.round(performance.now());
		T.events.push(data);
		if (T.events.length > 300) T.events.shift();
	}
	T.push = push;
	window.addEventListener('error', function (e) {
		push('js_error', { message: String(e.message || '').slice(0, 300),
			source: String(e.filename || '').slice(-120), line: e.lineno || 0 });
	});
	window.addEventListener('unhandledrejection', function (e) {
		var r = e.reason;
		push('js_unhandled_rejection', { message: String((r && r.message) || r).slice(0, 300) });
	});
	var resizeTimer = null;
	window.addEventListener('resize', function () {
		clearTimeout(resizeTimer);
		resizeTimer = setTimeout(function () {
			push('resize', { w: innerWidth, h: innerHeight, dpr: devicePixelRatio });
		}, 300);
	});
	if (screen.orientation && screen.orientation.addEventListener) {
		screen.orientation.addEventListener('change', function () {
			push('orientation', { type: screen.orientation.type, angle: screen.orientation.angle });
		});
	} else {
		window.addEventListener('orientationchange', function () {
			push('orientation', { angle: window.orientation });
		});
	}
	document.addEventListener('visibilitychange', function () {
		push('visibility', { state: document.visibilityState });
		if (document.visibilityState === 'hidden' && T.onHide) T.onHide();
	});
	window.addEventListener('pagehide', function () {
		push('pagehide', {});
		if (T.onHide) T.onHide();
	});
	window.addEventListener('blur', function () { push('focus', { focused: false }); });
	window.addEventListener('focus', function () { push('focus', { focused: true }); });
	document.addEventListener('fullscreenchange', function () {
		push('fullscreen', { on: !!document.fullscreenElement });
	});
	document.addEventListener('webkitfullscreenchange', function () {
		push('fullscreen', { on: !!document.webkitFullscreenElement });
	});
	// iOS Safari page-zoom pinch: a sign the browser is fighting the game.
	document.addEventListener('gesturestart', function () { push('browser_gesture', { type: 'gesturestart' }); });
	var c = document.getElementById('canvas') || document.querySelector('canvas');
	if (c) {
		c.addEventListener('webglcontextlost', function () { push('webgl_context_lost', {}); });
		c.addEventListener('webglcontextrestored', function () { push('webgl_context_restored', {}); });
	}
	T.drain = function () { var e = T.events; T.events = []; return JSON.stringify(e); };
	T.beacon = function (url, body) {
		try { return navigator.sendBeacon(url, new Blob([body], { type: 'text/plain' })); }
		catch (e) { return false; }
	};
	T.info = function () {
		return JSON.stringify({
			user_agent: navigator.userAgent, platform: navigator.platform || '',
			screen_w: screen.width, screen_h: screen.height,
			inner_w: innerWidth, inner_h: innerHeight, dpr: devicePixelRatio,
			max_touch_points: navigator.maxTouchPoints || 0,
			standalone: !!(window.navigator.standalone ||
				(window.matchMedia && matchMedia('(display-mode: standalone)').matches)),
			url_query: location.search, origin: location.origin
		});
	};
})();
"""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	session_id = "%08x%08x" % [randi(), Time.get_ticks_usec() & 0xFFFFFFFF]
	if FileAccess.file_exists("res://build_stamp.txt"):
		build_stamp = FileAccess.get_file_as_string("res://build_stamp.txt").strip_edges()
	var js_info := {}
	if OS.has_feature("web"):
		JavaScriptBridge.eval(JS_HOOKS, true)
		_js_tele = JavaScriptBridge.get_interface("__scTele")
		if _js_tele != null:
			_js_hide_cb = JavaScriptBridge.create_callback(_on_page_hide)
			_js_tele.onHide = _js_hide_cb
			var info = JavaScriptBridge.eval("window.__scTele.info()", true)
			if info is String:
				var parsed = JSON.parse_string(info)
				if parsed is Dictionary:
					js_info = parsed
			_url = str(js_info.get("origin", "")) + "/telemetry"
			enabled = _url.begins_with("http")
	else:
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--telemetry-url="):
				_url = a.substr("--telemetry-url=".length())
				enabled = true
	if not enabled:
		return
	_http = HTTPRequest.new()
	_http.timeout = 10.0
	add_child(_http)
	_http.request_completed.connect(_on_request_completed)
	get_tree().root.size_changed.connect(_on_viewport_resized)
	_send_session_start.call_deferred(js_info)


func _send_session_start(js_info: Dictionary) -> void:
	var vp := get_viewport().get_visible_rect().size
	var d := js_info.duplicate()
	d.erase("origin")
	d.merge({
		"build": build_stamp,
		"godot": Engine.get_version_info()["string"],
		"os": OS.get_name(),
		"model": OS.get_model_name(),
		"gpu": RenderingServer.get_video_adapter_name(),
		"gpu_vendor": RenderingServer.get_video_adapter_vendor(),
		"gpu_api": RenderingServer.get_video_adapter_api_version(),
		"renderer": str(ProjectSettings.get_setting("rendering/renderer/rendering_method", "")),
		"touchscreen": DisplayServer.is_touchscreen_available(),
		"window_w": DisplayServer.window_get_size().x,
		"window_h": DisplayServer.window_get_size().y,
		"viewport_w": int(vp.x),
		"viewport_h": int(vp.y),
		"screen_scale": DisplayServer.screen_get_scale(),
		"cmdline_args": " ".join(OS.get_cmdline_user_args()),
	})
	event("session_start", d)


## Queue one record. Cheap: no I/O happens here.
func event(kind: String, data: Dictionary = {}) -> void:
	if not enabled:
		return
	var r := {"session": session_id, "seq": _seq, "kind": kind, "t": Time.get_ticks_msec()}
	_seq += 1
	r.merge(data)
	_queue.append(r)
	if _queue.size() > MAX_QUEUE:
		_queue.pop_front()


func _process(delta: float) -> void:
	if not enabled:
		return
	_flush_timer += delta
	if _flush_timer >= FLUSH_SEC:
		_flush_timer = 0.0
		flush()


func _drain_js() -> void:
	if _js_tele == null:
		return
	var s = _js_tele.drain()
	if not (s is String) or s == "[]":
		return
	var arr = JSON.parse_string(s)
	if not (arr is Array):
		return
	for e in arr:
		if e is Dictionary:
			var kind := str(e.get("kind", "js_event"))
			e.erase("kind")
			event(kind, e)


## Send everything queued (skipped while a request is in flight).
func flush() -> void:
	if not enabled or _in_flight:
		return
	_drain_js()
	if _queue.is_empty():
		return
	var body := JSON.stringify({"records": _queue})
	_queue = []
	var err := _http.request(_url, PackedStringArray(["Content-Type: application/json"]),
		HTTPClient.METHOD_POST, body)
	if err == OK:
		_in_flight = true
	else:
		_note_failure()


func _on_request_completed(result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	_in_flight = false
	if result != HTTPRequest.RESULT_SUCCESS or code < 200 or code >= 300:
		_note_failure()
	else:
		_failures = 0


func _note_failure() -> void:
	_failures += 1
	if _failures >= MAX_FAILURES:
		enabled = false  # endpoint missing or unreachable: stop quietly


## Called from JS on visibilitychange(hidden) / pagehide. The main loop may
## not run again, so send synchronously with sendBeacon.
func _on_page_hide(_args) -> void:
	if not enabled or _js_tele == null:
		return
	page_hiding.emit()  # let the battle add a last perf sample / snapshot
	event("page_hide_flush", {})
	_drain_js()
	if _queue.is_empty():
		return
	var body := JSON.stringify({"records": _queue})
	_queue = []
	_js_tele.beacon(_url, body)


func _on_viewport_resized() -> void:
	var vp := get_viewport().get_visible_rect().size
	event("viewport_resize", {"viewport_w": int(vp.x), "viewport_h": int(vp.y),
		"window_w": DisplayServer.window_get_size().x, "window_h": DisplayServer.window_get_size().y})


func _notification(what: int) -> void:
	if not enabled:
		return
	match what:
		NOTIFICATION_APPLICATION_FOCUS_OUT:
			event("app_focus", {"focused": false})
		NOTIFICATION_APPLICATION_FOCUS_IN:
			event("app_focus", {"focused": true})
		NOTIFICATION_WM_CLOSE_REQUEST:
			flush()
