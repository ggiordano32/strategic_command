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

const DEFAULT_PORT := 8060
const PUBLIC_IP_URL := "https://api.ipify.org"

var pid := 0
var port := DEFAULT_PORT
var status := "Not running."
var running := false          ## the server answers /healthz
var public_ip := ""
var exe_override := ""        ## tests / --scserver=: another binary


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


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		if pid != 0:
			stop()
