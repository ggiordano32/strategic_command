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
var _dot: Kit.Dot
var _tag: Control
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


## The page is one trim panel (the kit's language): the Cinzel title, dim paragraphs with a rule between sections, the
## current server as a field row (the address and a "default" capsule), the status as a dot and a line, and the
## Back / Use default / Change buttons in one row.
func setup(p_net: Node) -> void:
	net = p_net
	custom_minimum_size.x = 640.0
	var panel := Kit.trim_panel(Color(0.06, 0.055, 0.045, 0.93), 14)
	panel.name = "server_panel"
	add_child(panel)
	var v := Kit.vbox(10)
	panel.add_child(v)
	v.add_child(Kit.title("Game server", 24))
	v.add_child(Kit.label("Online campaigns and live battles run on a game server. Host one yourself from the desktop version, or join a friend's. A default server is built in so a fresh install works.", 14, Kit.COL_DIM, true))
	if not Host.supported():
		var note := Kit.panel(Color(0.10, 0.085, 0.05, 0.9), 8)
		note.name = "server_note"
		note.add_child(Kit.label("Hosting a server needs the desktop version of the game (the web version can only join servers).", 13, Kit.COL_BONE, true))
		v.add_child(note)
	v.add_child(Kit.rule())
	if Host.supported():
		_build_host(v)
		v.add_child(Kit.rule())
	v.add_child(Kit.title("Join a friend's server", 19))
	var fld := PanelContainer.new()
	fld.name = "server_field"
	var fsb := Kit.box(Color(0.035, 0.03, 0.025, 0.96), 8.0, 4)
	fsb.set_border_width_all(1)
	fsb.border_color = Color(Kit.COL_RULE, 0.6)
	fld.add_theme_stylebox_override("panel", fsb)
	var fh := Kit.hbox(8)
	fld.add_child(fh)
	_current = Kit.label("", 16, Color.WHITE)
	_current.name = "server_current"
	_current.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_current.clip_text = true
	_current.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_current.custom_minimum_size.x = 40
	fh.add_child(_current)
	_tag = Kit.panel(Color(0.30, 0.22, 0.08, 1.0), 3)
	_tag.name = "server_default_tag"
	var tsb := Kit.box(Color(0.30, 0.22, 0.08, 1.0), 3.0, 9)
	tsb.content_margin_left = 8.0
	tsb.content_margin_right = 8.0
	tsb.set_border_width_all(1)
	tsb.border_color = Kit.COL_GOLD
	_tag.add_theme_stylebox_override("panel", tsb)
	_tag.add_child(Kit.label("default", 12, Kit.COL_GOLD))
	_tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	fh.add_child(_tag)
	v.add_child(fld)
	var sr := Kit.hbox(8)
	_dot = Kit.dot(Kit.COL_DIM)
	sr.add_child(_dot)
	_state = Kit.label("", 14, Kit.COL_DIM, true)
	_state.name = "server_state"
	_state.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sr.add_child(_state)
	v.add_child(sr)
	_build_edit(v)
	v.add_child(Kit.rule())
	v.add_child(Kit.title("The default server", 19))
	v.add_child(Kit.label("%s is built into the game so a fresh install works. It is one person's own server, like any other you could host." % Api.DEFAULT_SERVER, 14, Kit.COL_DIM, true))
	var br := Kit.hbox(8)
	var back := Kit.button("< Back", func(): back_requested.emit(), 0, 16)
	back.name = "server_back"
	Kit.nav_style(back)
	br.add_child(back)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	br.add_child(sp)
	var o := Kit.button("Use default", _use_default, 0, 16)
	o.name = "server_default"
	Kit.nav_style(o)
	br.add_child(o)
	var chg := Kit.button("Change", _toggle_edit, 0, 16)
	chg.name = "server_change"
	Kit.nav_style(chg)
	br.add_child(chg)
	v.add_child(br)
	refresh()


func _build_edit(parent: Control) -> void:
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
	parent.add_child(box)


func refresh() -> void:
	if net == null:
		return
	if is_inside_tree():
		custom_minimum_size.x = minf(640.0, get_viewport_rect().size.x - 32.0)   # (a phone: the screen's width)
	_current.text = net.server_url()
	_tag.visible = net.is_default()
	var col := Kit.COL_DIM
	if net.available:
		_state.text = Net_describe(net.info)
		col = Kit.COL_GOLD if bool(net.info.get("invite_required", false)) else Kit.COL_GOOD
		_state.add_theme_color_override("font_color", Kit.COL_GOOD)
	else:
		_state.text = "Not checked yet, or not reachable."
		_state.add_theme_color_override("font_color", Kit.COL_DIM)
	var t = net.launch.get("server_result", null)
	if t is Dictionary and not bool(t["ok"]):
		_state.text = str(t["text"])
		_state.add_theme_color_override("font_color", Kit.COL_BAD)
		col = Kit.COL_BAD
	_dot.set_col(col)
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

func _build_host(parent: Control) -> void:
	var box := Kit.vbox(8)
	box.add_child(Kit.title("Host a server", 19))
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
	parent.add_child(box)
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
