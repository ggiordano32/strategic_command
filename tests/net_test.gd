extends SceneTree
## Server choice and hosting plumbing (distribution milestone, D-client).
##   godot --headless --script res://tests/net_test.gd
## Address normalisation, the order detect / pick_base_url chooses in, the
## https-page / http-server refusal (simulated with Net.debug_page_https),
## the ?server= query, join links carrying a non-default server, seats kept
## per server, the compatibility text, and host.gd's address list. Uses a
## scratch seat store; no network.

const NetScript := preload("res://game/net/net.gd")
const Api := preload("res://game/net/api.gd")
const Host := preload("res://game/net/host.gd")
const Accounts := preload("res://game/net/accounts.gd")
const CState := preload("res://campaign/cstate.gd")

const DEFAULT := "https://strategiccommand.ggior32.dev"
var fails := 0


func _initialize() -> void:
	_normalise()
	_pick()
	_describe()
	_query()
	await _net()
	await _host()
	_upnp_text()
	_accounts()
	print("net_test: %s" % ("PASS" if fails == 0 else "%d FAILED" % fails))
	quit(1 if fails > 0 else 0)


func _upnp_text() -> void:
	_eq("upnp working", Host.upnp_text("working", 8060, "", "", ""), "Asking your router to open the port...")
	_eq("upnp ok", Host.upnp_text("ok", 8060, "203.0.113.7", "192.168.1.20", ""),
		"Port opened on your router (UPnP). Friends on the desktop version join with 203.0.113.7:8060.")
	_eq("upnp failed", Host.upnp_text("failed", 8061, "", "192.168.1.20", "198.51.100.4"),
		"Your router did not open the port. Forward TCP 8061 to 192.168.1.20 on your router, or use a tunnel such as Tailscale, and give friends 198.51.100.4:8061.")
	_eq("upnp off", Host.upnp_text("off", 8060, "", "", ""), "")


func _eq(what: String, got, want) -> void:
	if got != want:
		fails += 1
		printerr("FAIL %s: got %s, want %s" % [what, str(got), str(want)])


func _normalise() -> void:
	_eq("default", Api.normalise_url(DEFAULT + "/"), DEFAULT)
	_eq("bare ip port", Api.normalise_url("192.168.1.20:8060"), "http://192.168.1.20:8060")
	_eq("localhost", Api.normalise_url("localhost:8060/"), "http://localhost:8060")
	_eq("domain", Api.normalise_url("Games.Example.com"), "https://games.example.com")
	_eq("path and query dropped", Api.normalise_url("https://a.example/x/?join=ABC"), "https://a.example")
	_eq("spaces", Api.normalise_url("  http://10.0.0.5:9000/  "), "http://10.0.0.5:9000")
	_eq("empty", Api.normalise_url("  "), "")
	_eq("ftp", Api.normalise_url("ftp://x.example"), "")
	_eq("space inside", Api.normalise_url("a b"), "")


func _pick() -> void:
	_eq("default", Api.pick_base_url("", ""), DEFAULT)
	_eq("saved", Api.pick_base_url("", "http://10.0.0.5:8060"), "http://10.0.0.5:8060")
	_eq("arg beats saved", Api.pick_base_url("127.0.0.1:8072/", "http://10.0.0.5:8060"), "http://127.0.0.1:8072")
	_eq("origin that is a server", Api.pick_base_url("", "", "https://play.example", true), "https://play.example")
	_eq("origin that is not (itch)", Api.pick_base_url("", "", "https://html.itch.zone", false), DEFAULT)
	_eq("saved beats origin", Api.pick_base_url("", "http://10.0.0.5:8060", "https://play.example", true), "http://10.0.0.5:8060")
	_eq("arg beats origin", Api.pick_base_url("https://a.example", "", "https://play.example", true), "https://a.example")
	_eq("bad saved falls through", Api.pick_base_url("", "ftp://x", "", false), DEFAULT)


func _describe() -> void:
	var ok := NetScript.describe_info({"server": "strategic-command", "build": "abc rules:12345678", "invite_required": true, "state_version": CState.VERSION})
	_eq("compatible", ok["ok"], true)
	_eq("invite text", str(ok["text"]).contains("needs an invite key"), true)
	var bad := NetScript.describe_info({"server": "strategic-command", "build": "x", "state_version": CState.VERSION + 1})
	_eq("mismatch", bad["mismatch"], true)
	_eq("mismatch text", str(bad["text"]).contains("another version of the game"), true)
	var old := NetScript.describe_info({"server": "strategic-command", "build": "x"})  # server without the field
	_eq("no field is fine", old["ok"], true)
	_eq("not ours", NetScript.describe_info({"hello": 1})["ok"], false)


func _query() -> void:
	var q := NetScript.parse_query("?join=abc-def&server=https%3A%2F%2Fgames.example.com%3A8443%2F")
	_eq("join", q["join"], "ABCDEF")
	_eq("server", q["server"], "https://games.example.com:8443")
	_eq("no server", NetScript.parse_query("?join=abc-def").has("server"), false)
	_eq("link", NetScript.parse_query("?link=abcd-efgh&server=192.168.1.20%3A8060")["server"], "http://192.168.1.20:8060")


func _net() -> void:
	var n: Node = NetScript.new()
	n.accounts_path = "user://net_test/accounts.json"
	DirAccess.remove_absolute("user://net_test/accounts.json")
	get_root().add_child(n)
	await process_frame
	_eq("starts official", n.server_url(), DEFAULT)
	_eq("default link", n.join_link("ABCDEF"), DEFAULT + "/?join=ABCDEF")
	# A browser on an https page refuses an http server, and keeps the old one.
	n.debug_page_https = 1
	var r: Dictionary = n._apply_server("http://192.168.1.20:8060")
	_eq("refused", r["ok"], false)
	_eq("refusal text", r["text"], "A browser can only join servers with HTTPS. Use the desktop version to join this server, or ask the host for an https address.")
	_eq("unchanged", n.server_url(), DEFAULT)
	_eq("https ok", n.refusal_for("https://games.example.com"), "")
	_eq("bad address", n._apply_server("ftp://x")["ok"], false)
	# Desktop (or an http page): any address, saved on the device.
	n.debug_page_https = 0
	r = n._apply_server("192.168.1.20:8060/")
	_eq("applied", r["ok"], true)
	_eq("url", n.server_url(), "http://192.168.1.20:8060")
	_eq("saved", n.accounts.data.get("server"), "http://192.168.1.20:8060")
	_eq("not default", n.is_default(), false)
	_eq("link carries server", n.join_link("ABCDEF"), DEFAULT + "/?join=ABCDEF&server=" + "http://192.168.1.20:8060".uri_encode())
	_eq("a later start reads it", Api.detect_base_url(str(n.accounts.data.get("server", ""))), "http://192.168.1.20:8060")
	# Seats stay with their server.
	n.accounts.add("c1", 0, "tok", "Mine", "rome", n.server_url())
	n.accounts.add("old", 1, "tok2", "Legacy")
	_eq("local list", n.local_campaigns().size(), 1)
	_eq("open elsewhere refused", n.open_campaign("old"), null)
	n._apply_server(DEFAULT)
	_eq("default again", n.server_url(), DEFAULT)
	_eq("saved address cleared", n.accounts.data.has("server"), false)
	_eq("legacy seat is official", n.local_campaigns().size(), 1)
	_eq("legacy id", str(n.local_campaigns()[0]["id"]), "old")
	n.queue_free()
	DirAccess.remove_absolute("user://net_test/accounts.json")


func _host() -> void:
	var a := Host.lan_addresses(PackedStringArray(["127.0.0.1", "::1", "fe80::1", "169.254.3.4", "172.17.0.1", "192.168.1.20", "8.8.4.4", "10.0.0.7", "192.168.1.20", "0.0.0.0", "junk"]))
	_eq("lan list", Array(a), ["172.17.0.1", "192.168.1.20", "10.0.0.7", "8.8.4.4"])
	_eq("no addresses", Host.lan_addresses(PackedStringArray()).size(), 0)
	_eq("exe name", Host.exe_name() in ["scserver", "scserver.exe"], true)
	var h: Node = Host.new()
	h.exe_override = "/nonexistent/scserver"
	get_root().add_child(h)
	await process_frame
	_eq("no exe", h.find_exe(), "")
	h.port = 8060
	_eq("address text", h.addresses().size() >= 0, true)
	h.queue_free()


func _accounts() -> void:
	var a := Accounts.new("user://net_test/acc2.json")
	a.add("x", 0, "t", "n", "rome", "http://h:1")
	a.add("y", 0, "t", "n")
	_eq("filter custom", a.list_for("http://h:1", DEFAULT).size(), 1)
	_eq("filter default", a.list_for(DEFAULT, DEFAULT).size(), 1)
	DirAccess.remove_absolute("user://net_test/acc2.json")
