extends Node
## "Host a server" (desktop builds only): starts the bundled game server
## (scserver, or scserver.exe) beside the game executable as a child process,
## with its data in user://host/, serving the API only (no web build) to any
## origin. Friends on the desktop version join with this device's address
## over plain HTTP; browsers cannot (mixed content). The process is stopped
## when the game quits; a pid file in user://host/ lets the next start stop
## one left behind by a crash.
##
## View layer only: nothing here touches the campaign or battle sim.

signal status_changed
signal upnp_changed

const SETTINGS := "user://settings.cfg"
const UPNP_WORKING := "Asking your router to open the port..."

const DEFAULT_PORT := 8060
const PUBLIC_IP_URL := "https://api.ipify.org"

var pid := 0
var port := DEFAULT_PORT
var status := "Not running."
var running := false          ## the server answers /healthz
var public_ip := ""
var exe_override := ""        ## tests / --scserver=: another binary
var upnp_enabled := true      ## "Open port with UPnP" (settings.cfg [host] upnp)
var upnp_state := "off"       ## off | working | ok | failed
var upnp_external := ""       ## the router's external address when UPnP gave one
var _upnp: Object = null      ## the UPNP object that opened the port (kept to delete the mapping)
var _upnp_port := 0
var _upnp_thread: Thread = null
var _upnp_gen := 0


func _init() -> void:
	var cf := ConfigFile.new()
	if cf.load(SETTINGS) == OK:
		upnp_enabled = int(cf.get_value("host", "upnp", 1)) != 0


func set_upnp_enabled(on: bool) -> void:
	upnp_enabled = on
	var cf := ConfigFile.new()
	cf.load(SETTINGS)
	cf.set_value("host", "upnp", 1 if on else 0)
	cf.save(SETTINGS)


## The Host panel's UPnP line for a state (pure; tests call it). `external` is
## the router's address, `lan` this PC's network address, `public` the public
## address found some other way ("" when unknown).
static func upnp_text(state: String, p: int, external: String, lan: String, public: String) -> String:
	match state:
		"working":
			return UPNP_WORKING
		"ok":
			return "Port opened on your router (UPnP). Friends on the desktop version join with %s:%d." % [external, p]
		"failed":
			var who := lan if lan != "" else "this PC"
			var pub := public if public != "" else "<your public address>"
			return "Your router did not open the port. Forward TCP %d to %s on your router, or use a tunnel such as Tailscale, and give friends %s:%d." % [p, who, pub, p]
	return ""


## Ask the router to forward `port` (worker thread: discover() blocks for
## seconds). Never blocks the caller; upnp_changed fires when it is done.
func open_upnp() -> void:
	if not upnp_enabled or not running or not ClassDB.class_exists("UPNP"):
		if upnp_enabled and running:
			upnp_state = "failed"
			upnp_changed.emit()
		return
	_close_thread()
	upnp_state = "working"
	upnp_external = ""
	_upnp_gen += 1
	_upnp_thread = Thread.new()
	_upnp_thread.start(_upnp_open_work.bind(port, _upnp_gen))
	upnp_changed.emit()


func _upnp_open_work(p: int, gen: int) -> void:
	var u: Object = ClassDB.instantiate("UPNP")
	var ok := false
	var ext := ""
	if int(u.call("discover", 2000, 2, "InternetGatewayDevice")) == 0:
		var gw = u.call("get_gateway")
		if gw != null and bool(gw.call("is_valid_gateway")):
			if int(u.call("add_port_mapping", p, p, "Strategic Command", "TCP", 0)) == 0:
				ok = true
				ext = str(u.call("query_external_address"))
	call_deferred("_upnp_done", gen, ok, ext, u if ok else null, p)


func _upnp_done(gen: int, ok: bool, ext: String, u: Object, p: int) -> void:
	if _upnp_thread != null and _upnp_thread.is_started():
		_upnp_thread.wait_to_finish()  # it only has to return now
		_upnp_thread = null
	if gen != _upnp_gen or not running:
		if ok and u != null:  # stopped meanwhile: take the mapping away again
			_delete_in_thread(u, p)
		return
	upnp_state = "ok" if ok else "failed"
	_upnp = u
	_upnp_port = p
	upnp_external = ext if ext.is_valid_ip_address() and ext != "0.0.0.0" else ""
	if ok and upnp_external != "":
		public_ip = upnp_external
	upnp_changed.emit()


func _close_thread() -> void:
	if _upnp_thread != null and _upnp_thread.is_started() and not _upnp_thread.is_alive():
		_upnp_thread.wait_to_finish()
		_upnp_thread = null


var _del_threads: Array = []


func _delete_in_thread(u: Object, p: int) -> void:
	var t := Thread.new()
	_del_threads.append(t)
	t.start(func(): u.call("delete_port_mapping", p, "TCP"))


func _close_upnp() -> void:
	_upnp_gen += 1  # a discovery still running is ignored when it ends
	if _upnp != null:
		_delete_in_thread(_upnp, _upnp_port)
		_upnp = null
	if upnp_state != "off":
		upnp_state = "off"
		upnp_external = ""
		upnp_changed.emit()


## The server's file name: scserver.exe on Windows, scserver-arm64 /
## scserver-amd64 inside the macOS app (one per CPU), else scserver.
static func exe_name() -> String:
	match OS.get_name():
		"Windows":
			return "scserver.exe"
		"macOS":
			return "scserver-arm64" if Engine.get_architecture_name() == "arm64" else "scserver-amd64"
	return "scserver"


## The bundled server: beside the game executable, else (running from the
## editor) the repository's build/server/. "" when there is none.
func find_exe() -> String:
	if exe_override != "":
		return exe_override if FileAccess.file_exists(exe_override) else ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--scserver="):
			return a.get_slice("=", 1) if FileAccess.file_exists(a.get_slice("=", 1)) else ""
	var beside := OS.get_executable_path().get_base_dir().path_join(exe_name())
	if FileAccess.file_exists(beside):
		return beside
	var dev := ProjectSettings.globalize_path("res://build/server/" + exe_name())
	if FileAccess.file_exists(dev):
		return dev
	return ""


## Only desktop builds can run a server.
static func supported() -> bool:
	return not OS.has_feature("web") and OS.get_name() in ["Windows", "Linux", "macOS"]


## IPv4 addresses a friend on the same network can use: not loopback, not
## link-local (169.254.x.x), not "0.x"; private ones first.
static func lan_addresses(all: PackedStringArray) -> PackedStringArray:
	var out := PackedStringArray()
	for a in all:
		var p := a.split(".")
		if p.size() != 4 or not a.is_valid_ip_address():
			continue
		if p[0] == "127" or p[0] == "0" or (p[0] == "169" and p[1] == "254"):
			continue
		if not out.has(a):
			out.append(a)
	var priv := PackedStringArray()
	var rest := PackedStringArray()
	for a in out:
		var p := a.split(".")
		var is_priv: bool = p[0] == "10" or (p[0] == "192" and p[1] == "168") or (p[0] == "172" and int(p[1]) >= 16 and int(p[1]) <= 31)
		(priv if is_priv else rest).append(a)
	priv.append_array(rest)
	return priv


func addresses() -> PackedStringArray:
	var out := PackedStringArray()
	for a in lan_addresses(IP.get_local_addresses()):
		out.append("http://%s:%d" % [a, port])
	return out


func data_dir() -> String:
	return ProjectSettings.globalize_path("user://host")


func _set_status(s: String) -> void:
	status = s
	status_changed.emit()


## Start the server on `p` (1024..65535) and wait until it answers.
## -> {ok, text}.
func start(p: int, invite: String = "") -> Dictionary:
	if pid != 0:
		return {"ok": running, "text": status}
	if p < 1024 or p > 65535:
		return {"ok": false, "text": "Choose a port between 1024 and 65535."}
	var exe := find_exe()
	if exe == "":
		var why := "The server program (%s) was not found beside the game. Use the full download from the game's page." % exe_name()
		_set_status(why)
		return {"ok": false, "text": why}
	_stop_stale()
	port = p
	DirAccess.make_dir_recursive_absolute(data_dir())
	var args := PackedStringArray(["-addr", ":%d" % p, "-data", data_dir().path_join("data"),
		"-log-dir", data_dir().path_join("logs"), "-web=", "-allowed-origins=*"])
	if invite.strip_edges() != "":
		args.append_array(["-invite-key", invite.strip_edges()])
	pid = OS.create_process(exe, args)
	if pid <= 0:
		pid = 0
		_set_status("The server could not be started.")
		return {"ok": false, "text": status}
	var f := FileAccess.open(data_dir().path_join("pid"), FileAccess.WRITE)
	if f != null:
		f.store_string(str(pid))
		f.close()
	_set_status("Starting...")
	for i in 40:  # up to ~10 s
		await get_tree().create_timer(0.25).timeout
		if not OS.is_process_running(pid):
			pid = 0
			_set_status("The server stopped at once. Is port %d already in use?" % p)
			return {"ok": false, "text": status}
		if await _healthy():
			running = true
			_set_status("Running on port %d." % p)
			open_upnp.call_deferred()
			return {"ok": true, "text": status}
	stop()
	_set_status("The server did not answer in time.")
	return {"ok": false, "text": status}


func _healthy() -> bool:
	var req := HTTPRequest.new()
	req.timeout = 2.0
	add_child(req)
	if req.request("http://127.0.0.1:%d/healthz" % port) != OK:
		req.queue_free()
		return false
	var out: Array = await req.request_completed
	req.queue_free()
	return int(out[0]) == HTTPRequest.RESULT_SUCCESS and int(out[1]) == 200


func stop() -> void:
	_close_upnp()
	if pid != 0:
		OS.kill(pid)
		pid = 0
	running = false
	DirAccess.remove_absolute(data_dir().path_join("pid"))
	_set_status("Not running.")


## A server left by a game that crashed (or was terminated): stop it before
## starting another, if the pid still belongs to a scserver.
func _stop_stale() -> void:
	var p := data_dir().path_join("pid")
	if FileAccess.file_exists(p):
		var old := int(FileAccess.get_file_as_string(p).strip_edges())
		if old > 0 and _is_scserver(old):
			OS.kill(old)
		DirAccess.remove_absolute(p)


## Is this pid a running scserver? (OS.is_process_running only knows our own children.)
static func _is_scserver(p: int) -> bool:
	var out: Array = []
	match OS.get_name():
		"Windows":
			OS.execute("tasklist", ["/FI", "PID eq %d" % p, "/NH"], out)
		_:
			OS.execute("ps", ["-p", str(p), "-o", "comm="], out)
	return str(out).contains("scserver")


## This network's public address as seen from outside (best effort); "" when
## it could not be found.
func fetch_public_ip() -> String:
	var req := HTTPRequest.new()
	req.timeout = 6.0
	add_child(req)
	if req.request(PUBLIC_IP_URL) != OK:
		req.queue_free()
		return ""
	var out: Array = await req.request_completed
	req.queue_free()
	if int(out[0]) != HTTPRequest.RESULT_SUCCESS or int(out[1]) != 200:
		return ""
	var t: String = (out[3] as PackedByteArray).get_string_from_utf8().strip_edges()
	public_ip = t if t.is_valid_ip_address() else ""
	return public_ip


func _exit_tree() -> void:
	if pid != 0:
		stop()
	for t in _del_threads:  # let the router mapping be removed before quitting
		if (t as Thread).is_started():
			(t as Thread).wait_to_finish()
	_del_threads.clear()
	if _upnp_thread != null and _upnp_thread.is_started():
		_upnp_thread.wait_to_finish()  # (bounded by discover()'s timeout)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		if pid != 0:
			stop()
