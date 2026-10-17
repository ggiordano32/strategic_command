extends VBoxContainer
## The "Game server" menu page: which server this device plays on (the
## default one unless changed; Change opens an address field with Paste, Test
## and Use default), and on desktop builds "Host a server" (host.gd).
## View layer: it only calls Net.

signal back_requested

const Kit := preload("res://game/campaign/ui_kit.gd")
const Api := preload("res://game/net/api.gd")
const Host := preload("res://game/net/host.gd")

var net: Node
var _current: Label
var _state: Label
var _edit_box: Control
var _edit: LineEdit
var _result: Label
var _host_port: LineEdit
var _host_invite: LineEdit
var _host_start: Button
var _host_stop: Button
var _host_status: Label
var _host_addrs: VBoxContainer
var _host_upnp_check: CheckBox
var _host_upnp: Label
var _host_retry: Button
var _busy := false


func _init() -> void:
	add_theme_constant_override("separation", 10)


func setup(p_net: Node) -> void:
	net = p_net
	add_child(Kit.label("Game server", 22, Kit.COL_GOLD))
	add_child(Kit.label("Online campaigns and live battles run on a game server. Host one yourself from the desktop version, or join a friend's. A default server is built in so a fresh install works.", 14, Kit.COL_DIM, true))
	if Host.supported():
		_build_host()
		add_child(HSeparator.new())
	else:
		add_child(Kit.label("Hosting a server needs the desktop version of the game (the web version can only join servers).", 13, Kit.COL_DIM, true))
	add_child(Kit.label("Join a friend's server", 19, Kit.COL_GOLD))
	var row := Kit.flow(8)
	_current = Kit.label("", 17, Color.WHITE)
	_current.name = "server_current"
	row.add_child(_current)
	var chg := Kit.button("Change", _toggle_edit, 110)
	chg.name = "server_change"
	row.add_child(chg)
	add_child(row)
	_state = Kit.label("", 14, Kit.COL_DIM, true)
	_state.name = "server_state"
	add_child(_state)
	_build_edit()
	add_child(HSeparator.new())
	add_child(Kit.label("The default server", 19, Kit.COL_GOLD))
	add_child(Kit.label("%s is built into the game so a fresh install works. It is one person's own server, like any other you could host." % Api.DEFAULT_SERVER, 14, Kit.COL_DIM, true))
	var o := Kit.button("Use default", _use_default, 150)
	o.name = "server_default"
	add_child(o)
	var back := Kit.button("< Back", func(): back_requested.emit(), 150)
	add_child(back)
	refresh()


func _build_edit() -> void:
	var box := Kit.vbox(8)
	box.visible = false
	_edit_box = box
	_edit = Kit.text_field("https://example.com or 192.168.1.20:8060", "", 380, "Server address", true)
	_edit.name = "server_edit"
	_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(Kit.field_box(_edit))
	var r := Kit.flow(8)
	var t := Kit.button("Test", _test, 100)
	t.name = "server_test"
	r.add_child(t)
	var u := Kit.button("Use this server", _use, 170)
	u.name = "server_use"
	r.add_child(u)
	box.add_child(r)
	_result = Kit.label("", 14, Kit.COL_DIM, true)
	_result.name = "server_result"
	box.add_child(_result)
	box.add_child(Kit.label("Browsers (including the game on itch.io) can only join servers with an https address. The desktop version can join any address, such as a friend's 192.168.1.20:8060.", 13, Kit.COL_DIM, true))
	add_child(box)


func refresh() -> void:
	if net == null:
		return
	_current.text = "Server: %s%s" % [net.server_url(), " (default)" if net.is_default() else ""]
	if net.available:
		_state.text = Net_describe(net.info)
		_state.add_theme_color_override("font_color", Kit.COL_GOOD)
	else:
		_state.text = "Not checked yet, or not reachable."
		_state.add_theme_color_override("font_color", Kit.COL_DIM)
	var t = net.launch.get("server_result", null)
	if t is Dictionary and not bool(t["ok"]):
		_state.text = str(t["text"])
		_state.add_theme_color_override("font_color", Kit.COL_BAD)
	if Host.supported() and _host_status != null:
		_refresh_host()


func Net_describe(info: Dictionary) -> String:
	return str(net.describe_info(info)["text"])


func _toggle_edit() -> void:
	_edit_box.visible = not _edit_box.visible
	if _edit_box.visible:
		_edit.text = "" if net.is_default() else net.server_url()


func _say(text: String, good: bool) -> void:
	_result.text = text
	_result.add_theme_color_override("font_color", Kit.COL_GOOD if good else Kit.COL_BAD)


func _test() -> void:
	if _busy:
		return
	_busy = true
	_say("Testing...", true)
	var r: Dictionary = await net.test_server(_edit.text)
	_busy = false
	_say(str(r["text"]), bool(r["ok"]))


func _use() -> void:
	await _switch(_edit.text)


func _use_default() -> void:
	_edit.text = Api.DEFAULT_SERVER
	await _switch(Api.DEFAULT_SERVER)


func _switch(url: String) -> void:
	if _busy:
		return
	_busy = true
	_say("Connecting...", true)
	var r: Dictionary = await net.set_server(url)
	_busy = false
	net.launch.erase("server_result")
	_say(str(r["text"]), bool(r["ok"]))
	refresh()


# ------------------------------------------------------------------ host ---

func _build_host() -> void:
	var box := Kit.vbox(8)
	box.add_child(Kit.label("Host a server", 19, Kit.COL_GOLD))
	box.add_child(Kit.label("Friends on the desktop version join with this address. Outside your network the game asks your router to open the port (UPnP); if that fails, forward the port yourself or use a tunnel like Tailscale. Browser players cannot join a plain-HTTP server.", 14, Kit.COL_DIM, true))
	var r := Kit.flow(8)
	r.add_child(Kit.label("Port", 15))
	_host_port = Kit.text_field("8060", str(Host.DEFAULT_PORT), 90, "Port")
	_host_port.name = "host_port"
	r.add_child(_host_port)
	_host_invite = Kit.text_field("Invite key (optional)", "", 220, "Invite key", true)
	_host_invite.name = "host_invite"
	r.add_child(Kit.field_box(_host_invite))
	box.add_child(r)
	var r2 := Kit.flow(8)
	_host_start = Kit.button("Start", _host_do_start, 120)
	_host_start.name = "host_start"
	r2.add_child(_host_start)
	_host_stop = Kit.button("Stop", _host_do_stop, 120)
	_host_stop.name = "host_stop"
	r2.add_child(_host_stop)
	box.add_child(r2)
	_host_upnp_check = CheckBox.new()
	_host_upnp_check.text = "Open port with UPnP"
	_host_upnp_check.name = "host_upnp_check"
	_host_upnp_check.button_pressed = (net.get_host() as Host).upnp_enabled
	_host_upnp_check.toggled.connect(_on_upnp_toggled)
	box.add_child(_host_upnp_check)
	_host_status = Kit.label("", 14, Kit.COL_DIM, true)
	_host_status.name = "host_status"
	box.add_child(_host_status)
	var ur := Kit.flow(8)
	_host_upnp = Kit.label("", 14, Kit.COL_DIM, true)
	_host_upnp.name = "host_upnp"
	ur.add_child(_host_upnp)
	_host_retry = Kit.button("Try again", func(): (net.get_host() as Host).open_upnp(), 120)
	_host_retry.name = "host_upnp_retry"
	ur.add_child(_host_retry)
	box.add_child(ur)
	_host_addrs = Kit.vbox(6)
	box.add_child(_host_addrs)
	add_child(box)
	(net.get_host() as Host).upnp_changed.connect(_on_upnp_changed)
	_refresh_host()


func _on_upnp_toggled(on: bool) -> void:
	var h: Host = net.get_host()
	h.set_upnp_enabled(on)
	if h.running:
		if on:
			h.open_upnp()
		else:
			h._close_upnp()
	_refresh_host()


func _on_upnp_changed() -> void:
	if _host_upnp == null:
		return
	_refresh_host()


## This PC's first network address ("" when none) and the public one if known.
func _upnp_line() -> String:
	var h: Host = net.get_host()
	var lan := lan_first()
	return Host.upnp_text(h.upnp_state, h.port, h.upnp_external, lan, h.public_ip)


static func lan_first() -> String:
	var l := Host.lan_addresses(IP.get_local_addresses())
	return l[0] if not l.is_empty() else ""


func _refresh_host() -> void:
	var h: Host = net.get_host()
	_host_status.text = h.status
	_host_start.disabled = h.pid != 0
	_host_stop.disabled = h.pid == 0
	var show_upnp := h.running and h.upnp_enabled and h.upnp_state != "off"
	_host_upnp.visible = show_upnp
	_host_upnp.text = _upnp_line()
	_host_upnp.add_theme_color_override("font_color", Kit.COL_GOOD if h.upnp_state == "ok" else (Kit.COL_BAD if h.upnp_state == "failed" else Kit.COL_DIM))
	_host_retry.visible = show_upnp and h.upnp_state == "failed"
	for c in _host_addrs.get_children():
		c.queue_free()
	if not h.running:
		return
	_host_addrs.add_child(Kit.label("Your server is running. This device is using it.", 14, Kit.COL_GOOD))
	_host_addrs.add_child(Kit.label("Same network:", 14, Kit.COL_DIM))
	var addrs := h.addresses()
	if addrs.is_empty():
		_host_addrs.add_child(Kit.label("(no network address found)", 14, Kit.COL_DIM))
	for a in addrs:
		_host_addrs.add_child(_addr_row(a))
	var pub := Kit.flow(8)
	pub.name = "host_public"
	_host_addrs.add_child(pub)
	if h.public_ip != "":
		_host_addrs.remove_child(pub)
		pub.queue_free()
		_host_addrs.add_child(Kit.label("Over the internet:" if h.upnp_state == "ok" else "Over the internet (after forwarding the port):", 14, Kit.COL_DIM))
		_host_addrs.add_child(_addr_row("http://%s:%d" % [h.public_ip, h.port]))
	else:
		pub.add_child(Kit.label("Looking up your public address...", 14, Kit.COL_DIM))
		_load_public(h)


func _load_public(h: Host) -> void:
	var ip: String = await h.fetch_public_ip()
	if not is_inside_tree():
		return
	if ip == "":
		for c in _host_addrs.get_children():
			if c.name == "host_public":
				for k in c.get_children():
					k.queue_free()
				c.add_child(Kit.label("Public address not found (no internet, or the lookup is blocked).", 14, Kit.COL_DIM))
	else:
		_refresh_host()


func _addr_row(a: String) -> Control:
	var r := Kit.flow(8)
	r.add_child(Kit.label(a, 16, Color.WHITE))
	r.add_child(Kit.button("Copy", func(): DisplayServer.clipboard_set(a), 90, Kit.FONT_SMALL))
	return r


func _host_do_start() -> void:
	if _busy:
		return
	_busy = true
	var h: Host = net.get_host()
	_host_status.text = "Starting..."
	var res: Dictionary = await h.start(int(_host_port.text), _host_invite.text)
	_busy = false
	if res["ok"]:
		var r: Dictionary = await net.set_server("http://127.0.0.1:%d" % h.port)
		_say(str(r["text"]), bool(r["ok"]))
	refresh()


## Testing aid (--host-start=PORT): what pressing Start does, with the result printed.
func autostart(p: int) -> void:
	if _host_port == null:
		print("HOST_RESULT unsupported")
		return
	_host_port.text = str(p)
	await _host_do_start()
	var h: Host = net.get_host()
	for i in 80:  # up to ~20 s for the UPnP attempt
		if h.upnp_state != "working" and (h.upnp_state != "off" or not h.upnp_enabled):
			break
		await get_tree().create_timer(0.25).timeout
	print("HOST_UPNP state=%s text=%s" % [h.upnp_state, _host_upnp.text if _host_upnp.visible else "(hidden)"])
	print("HOST_RESULT running=%s status=%s server=%s available=%s addrs=%s" % [h.running, h.status, net.server_url(), net.available, ",".join(h.addresses())])


func _host_do_stop() -> void:
	var h: Host = net.get_host()
	var mine: bool = net.server_url() == "http://127.0.0.1:%d" % h.port
	h.stop()
	if mine:
		await net.set_server(Api.DEFAULT_SERVER)
	refresh()
