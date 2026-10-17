extends Node
## Online play (autoload "Net"): the API client, this device's seats
## (accounts.gd), the build and rules versions, and the calls that are not
## about one open campaign: server info, create, join, device codes, and
## the status badges of the Continue list. One OnlineCampaign at a time is
## open (`current`).
##
## Versions: a campaign's state format (pinned by the server when it is
## created) must be one this build reads (CState.MIN_VERSION..VERSION) or
## the campaign is refused; online states are never migrated. `rules` is a hash of campaign/*.gd
## and sim/*.gd (from build_stamp.txt in exported builds, computed from the
## sources otherwise); a different rules hash from the one that made the
## latest version is shown as a warning, and the determinism check reports
## any actual divergence.

const Api := preload("res://game/net/api.gd")
const Accounts := preload("res://game/net/accounts.gd")
const Host := preload("res://game/net/host.gd")
const OnlineCampaign := preload("res://game/net/online_campaign.gd")
const CState := preload("res://campaign/cstate.gd")
const CData := preload("res://campaign/cdata.gd")

## Join codes are 6 and device codes 8 characters from this alphabet (no
## 0/O, 1/I/L, U/V lookalikes); typing is case-insensitive.
const CODE_ALPHABET := "23456789ABCDEFGHJKMNPQRSTWXYZ"

var api: Api
var accounts: Accounts
var accounts_path := ""
var rules := ""
var build := "dev"
var info: Dictionary = {}       ## /api/info, once fetched
var available := false          ## the server answered /api/info
var new_build_available := false
var current: OnlineCampaign = null
var badges := {}                ## id -> {text, color, summary}
var launch := {}                ## from the page URL: {"join": code} or {"link": code}, {"server": url}
var host: Host = null           ## the server this device runs (desktop), once created
var debug_page_https := -1      ## test aid: 1 / 0 pretend the page is / is not https (-1: ask the browser)
var _origin_probed := false
var _resolving := false
var cache_dir := "user://online/"


func _ready() -> void:
	api = Api.new()
	add_child(api)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--accounts="):
			# Testing aid: another seat store (and cache next to it).
			accounts_path = a.get_slice("=", 1)
			cache_dir = accounts_path.get_base_dir().path_join("cache") + "/"
	accounts = Accounts.new(accounts_path)
	api.base_url = Api.detect_base_url(str(accounts.data.get("server", "")))
	if FileAccess.file_exists("res://build_stamp.txt"):
		build = FileAccess.get_file_as_string("res://build_stamp.txt").strip_edges()
	rules = rules_hash(build)
	if OS.has_feature("web"):
		var q = JavaScriptBridge.eval("window.location.search", true)
		if q is String:
			launch.merge(parse_query(q))
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--join="):
			launch["join"] = norm_code(a.get_slice("=", 1))
		elif a.begins_with("--link="):
			launch["link"] = norm_code(a.get_slice("=", 1))
		elif a.begins_with("--launch-server="):
			launch["server"] = Api.normalise_url(a.get_slice("=", 1))  # testing aid: like ?server= on the web
		elif a.begins_with("--nettest="):
			launch["nettest"] = a.get_slice("=", 1)  # testing aid (net_selftest.gd)


## The launch values of a page URL's query ("?join=ABC-DEF&server=https%3A%2F%2F...").
static func parse_query(q: String) -> Dictionary:
	var out := {}
	for kv in q.trim_prefix("?").split("&"):
		var k := kv.get_slice("=", 0)
		if k in ["join", "link", "custom"] and kv.contains("="):
			out[k] = norm_code(kv.get_slice("=", 1).uri_decode())
		elif k == "server" and kv.contains("="):
			out[k] = Api.normalise_url(kv.get_slice("=", 1).uri_decode())
		elif k in ["nettest", "campaign", "token", "invite"] and kv.contains("="):
			out[k] = kv.get_slice("=", 1).uri_decode()  # browser self-test (net_selftest.gd)
	return out


## Rules hash: "rules:xxxxxxxx" from the build stamp, else SHA-1 of
## campaign/*.gd + campaign/data/*.gd + sim/*.gd (sorted paths, concatenated), first 8 hex digits
## (tools/export_web.sh computes the same).
static func rules_hash(stamp: String = "") -> String:
	for part in stamp.split(" "):
		if part.begins_with("rules:"):
			return part.substr(6)
	var paths: Array[String] = []
	for dir in ["campaign", "campaign/data", "sim"]:
		for fn in DirAccess.get_files_at("res://" + dir):
			if fn.ends_with(".gd"):
				paths.append(dir + "/" + fn)
	paths.sort()
	if paths.is_empty():
		return "unknown"
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA1)
	for p in paths:
		var b := FileAccess.get_file_as_bytes("res://" + p)
		if b.is_empty():
			return "unknown"
		ctx.update(b)
	return ctx.finish().hex_encode().substr(0, 8)


static func norm_code(s: String) -> String:
	var out := ""
	for ch in s.to_upper():
		if CODE_ALPHABET.contains(ch):
			out += ch
	return out


## Pretty form for showing: ABC-DEF / ABCD-EFGH.
static func show_code(c: String) -> String:
	var h := c.length() / 2
	return c.substr(0, h) + "-" + c.substr(h)


## The server this device can run for friends (desktop; see host.gd).
func get_host() -> Host:
	if host == null:
		host = Host.new()
		host.name = "Host"
		add_child(host)
	return host


func has_server() -> bool:
	return api != null and api.base_url != ""


## The game server this device uses (no trailing slash).
func server_url() -> String:
	return api.base_url if api != null else ""


func is_default() -> bool:
	return server_url() == Api.DEFAULT_SERVER


## Where the web game is played, for share links: the default server serves it.
func site_url() -> String:
	return Api.DEFAULT_SERVER


## A link that opens the game on this server: the default page, with
## ?server= when the server is another one (a pasted link works in the Join
## page as well, which reads the code and the server from it).
func _link(key: String, code: String) -> String:
	var l := "%s/?%s=%s" % [site_url(), key, code]
	if not is_default() and server_url() != "":
		l += "&server=" + server_url().uri_encode()
	return l


func join_link(code: String) -> String:
	return _link("join", code)


func device_link(code: String) -> String:
	return _link("link", code)


## The campaigns of this device that live on the chosen server.
func local_campaigns() -> Array:
	return accounts.list_for(server_url(), Api.DEFAULT_SERVER)


func _page_https() -> bool:
	if debug_page_https >= 0:
		return debug_page_https == 1
	if OS.has_feature("web"):
		var p = JavaScriptBridge.eval("window.location.protocol", true)
		return p is String and p == "https:"
	return false


func _page_origin() -> String:
	if OS.has_feature("web"):
		var o = JavaScriptBridge.eval("window.location.origin", true)
		if o is String and (o as String).begins_with("http"):
			return o
	return ""


## Why a page cannot use this server ("" when it can): a browser on an
## https page cannot call a plain-http server (mixed content).
func refusal_for(url: String) -> String:
	if (OS.has_feature("web") or debug_page_https >= 0) and _page_https() and url.begins_with("http://"):
		return "A browser can only join servers with HTTPS. Use the desktop version to join this server, or ask the host for an https address."
	return ""


## What /api/info says about a server, as text for the Server row:
## {ok, text, mismatch, invite_required}. `d` is the info dictionary.
static func describe_info(d: Dictionary) -> Dictionary:
	if str(d.get("server", "")) != "strategic-command":
		return {"ok": false, "mismatch": false, "invite_required": false,
			"text": "That address answers, but it is not a Strategic Command game server."}
	var txt := "Game server %s" % str(d.get("build", "")).get_slice(" ", 0)
	var sv := int(d.get("state_version", 0))
	var mismatch := d.has("state_version") and sv != CState.VERSION
	var invite := bool(d.get("invite_required", false))
	if mismatch:
		return {"ok": false, "mismatch": true, "invite_required": invite,
			"text": "This server is for another version of the game (campaign format %d, this game uses %d). Update the game or use another server." % [sv, CState.VERSION]}
	txt += ", ready. "
	txt += "Creating a campaign needs an invite key." if invite else "No invite key needed."
	return {"ok": true, "mismatch": false, "invite_required": invite, "text": txt}


## Ask a server (not necessarily the chosen one) what it is, without
## switching to it. -> {ok, reachable, text, mismatch, invite_required, info}.
func test_server(url: String) -> Dictionary:
	var u := Api.normalise_url(url)
	if u == "":
		return {"ok": false, "reachable": false, "mismatch": false, "invite_required": false, "info": {}, "text": "That does not look like a server address. Try https://example.com or 192.168.1.20:8060."}
	var why := refusal_for(u)
	if why != "":
		return {"ok": false, "reachable": false, "mismatch": false, "invite_required": false, "info": {}, "text": why}
	var r: Dictionary = await api.call_api("GET", "/api/info", null, "", {"timeout": 8, "retries": 1, "base": u})
	if not r["ok"] or not (r["data"] is Dictionary):
		return {"ok": false, "reachable": not r["network"], "mismatch": false, "invite_required": false, "info": {},
			"text": "Cannot reach %s (%s)." % [u, "no answer" if r["network"] else "it answered %d" % int(r["status"])]}
	var d := describe_info(r["data"])
	d["reachable"] = true
	d["info"] = r["data"]
	return d


## Use another server (or the default one: DEFAULT_SERVER). Saved on this
## device. -> {ok, text}; nothing changes when refused.
func set_server(url: String) -> Dictionary:
	var res := _apply_server(url)
	if not res["ok"]:
		return res
	var ok := await check_server()
	return {"ok": ok, "text": describe_info(info)["text"] if ok else "Cannot reach %s." % server_url()}


func _apply_server(url: String) -> Dictionary:
	var u := Api.normalise_url(url)
	if u == "":
		return {"ok": false, "text": "That does not look like a server address. Try https://example.com or 192.168.1.20:8060."}
	var why := refusal_for(u)
	if why != "":
		return {"ok": false, "text": why}
	if u != api.base_url:
		api.base_url = u
		available = false
		info = {}
		new_build_available = false
		if u == Api.DEFAULT_SERVER:
			accounts.data.erase("server")
			accounts.save()
		else:
			accounts.set_value("server", u)
	_origin_probed = true
	return {"ok": true, "text": ""}


## Fetch /api/info (server reachable? invite key needed? newer web build?).
## The first call on the web, with no address chosen, first looks at the
## page's own origin: if that is a game server (our own site), use it.
func check_server() -> bool:
	while _resolving:  # a first call is still choosing the address
		await get_tree().process_frame
	if not _origin_probed:
		_origin_probed = true
		_resolving = true
		var o := _page_origin()
		var chosen := false
		for a in OS.get_cmdline_user_args():
			chosen = chosen or a.begins_with("--server=")
		if o != "" and not chosen and str(accounts.data.get("server", "")) == "" and not launch.has("server"):
			var pr: Dictionary = await api.call_api("GET", "/api/info", null, "", {"timeout": 6, "retries": 0, "base": o})
			if pr["ok"] and pr["data"] is Dictionary and str(pr["data"].get("server", "")) == "strategic-command":
				api.base_url = Api.pick_base_url("", "", o, true)
		if launch.has("server") and str(launch["server"]) != "" and launch["server"] != api.base_url:
			launch["server_result"] = _apply_server(str(launch["server"]))
		_resolving = false
	if not has_server():
		available = false
		return false
	var r: Dictionary = await api.call_api("GET", "/api/info", null, "", {"timeout": 8, "retries": 1})
	available = r["ok"] and r["data"] is Dictionary and str(r["data"].get("server", "")) == "strategic-command"
	if available:
		info = r["data"]
		var sb := str(info.get("build", ""))
		# Only a server that also serves this page can say the page is old.
		new_build_available = OS.has_feature("web") and server_url() == _page_origin() and sb != "" and build != "dev" and sb != build
	return available


func labels() -> Dictionary:
	var fs: Array = []
	for i in CData.faction_count():
		fs.append(CData.faction_name(i))
	var rs: Array = []
	for r in CData.region_count():
		rs.append(str(CData.REGIONS[r]["city"]))
	return {"factions": fs, "regions": rs}


## Create an online campaign from a state (new, or a local one being moved
## online). opts: {webhook_url, discord_user, invite, name}. Returns the API
## result; on success the seat is stored on this device.
func create_campaign(st: Dictionary, seat: int, opts: Dictionary = {}) -> Dictionary:
	CData.use_state(st)  # labels() names the state's pack's factions and cities
	var text := CState.to_json(st)
	var body := {"name": str(opts.get("name", st.get("name", ""))), "format_version": int(st.get("version", CState.VERSION)), "rules": rules,
		"build": build, "seat": seat, "state_gz": OnlineCampaign.gz64(text), "hash": CState.hash_text(st),
		"labels": labels(), "turn_timeout_h": int(st["settings"].get("turn_timeout_h", 0)),
		"device": accounts.device()}
	for k in ["webhook_url", "discord_user", "invite"]:
		if str(opts.get(k, "")) != "":
			body[k] = str(opts[k])
	var r: Dictionary = await api.call_api("POST", "/api/campaigns", body, "", {"timeout": 30})
	if r["ok"]:
		var d: Dictionary = r["data"]
		accounts.add(str(d["id"]), seat, str(d["token"]), str(body["name"]), str(st.get("pack", "rome")), server_url())
		_seed_cache(str(d["id"]), st, int(d["version"]))
		if str(opts.get("invite", "")) != "":
			accounts.set_value("invite", str(opts["invite"]))
	return r


func _seed_cache(cid: String, st: Dictionary, v: int) -> void:
	var oc := OnlineCampaign.new()
	oc.id = cid
	oc.cache_dir = cache_dir
	oc.st = st
	oc.version = v
	oc.state_hash = CState.hash_text(st)
	oc.mine[str(v)] = 1
	oc._save_cache()
	oc.free()


func join_preview(code: String) -> Dictionary:
	return await api.call_api("POST", "/api/join/preview", {"code": norm_code(code)}, "", {"retries": 1})


func join(code: String, seat: int, discord_user: String = "") -> Dictionary:
	var body := {"code": norm_code(code), "f": seat, "device": accounts.device()}
	if discord_user != "":
		body["discord_user"] = discord_user
	var r: Dictionary = await api.call_api("POST", "/api/join", body, "", {})
	if r["ok"]:
		accounts.add(str(r["data"]["id"]), seat, str(r["data"]["token"]), str(r["data"].get("name", "")), "rome", server_url())
	return r


## Claim a device code: this device gets its own key for that seat.
func claim_link(code: String) -> Dictionary:
	var r: Dictionary = await api.call_api("POST", "/api/link", {"code": norm_code(code), "device": accounts.device()}, "", {})
	if r["ok"]:
		accounts.add(str(r["data"]["id"]), int(r["data"]["seat"]), str(r["data"]["token"]), str(r["data"].get("name", "")), "rome", server_url())
	return r


## Open (or return the open) campaign controller for a stored seat.
func open_campaign(cid: String) -> OnlineCampaign:
	if current != null and current.id == cid:
		return current
	close_campaign()
	var e := accounts.get_entry(cid)
	if e.is_empty() or str(e.get("server", Api.DEFAULT_SERVER)) != server_url():
		return null
	current = OnlineCampaign.new()
	current.setup(api, cid, int(e["f"]), str(e["token"]), rules, build)
	current.cache_dir = cache_dir
	add_child(current)
	return current


func close_campaign() -> void:
	if current != null:
		current.close()
		var c := current
		current = null
		get_tree().create_timer(5.0).timeout.connect(func(): if is_instance_valid(c): c.queue_free())


## Badge for a campaign summary: [text, colour].
static func badge_for(s: Dictionary) -> Array:
	var me := int(s.get("me", -1))
	var phase := str(s.get("phase", ""))
	if phase == "over":
		return ["Won", Color(0.6, 0.95, 0.6)] if int(s.get("winner", -1)) == 1 else ["Lost", Color(1.0, 0.6, 0.5)]
	var names := {}
	for seat in s.get("seats", []):
		names[int(seat["f"])] = str(seat["name"])
	if phase == "battles":
		var mine := 0
		var n := 0
		for b in s.get("battles", []):
			n += 1
			if (b["humans"] as Array).has(me):
				mine += 1
		return ["%d battle%s pending" % [n, "" if n == 1 else "s"], Color(1.0, 0.7, 0.45) if mine > 0 else Color(0.85, 0.85, 0.8)]
	var open_seat := false
	for seat in s.get("seats", []):
		if not bool(seat.get("claimed", true)):
			open_seat = true
	if open_seat:
		return ["Waiting for players to join", Color(0.85, 0.85, 0.8)]
	if bool(s.get("all_in", false)):
		return ["Resolving", Color(0.75, 0.85, 1.0)]
	if (s.get("submitted", []) as Array).has(me):
		var waiting: Array[String] = []
		for f in s.get("missing", []):
			waiting.append(str(names.get(int(f), "ally")))
		return ["Waiting for " + " and ".join(waiting), Color(0.85, 0.85, 0.8)]
	return ["Your turn", Color(1.0, 0.85, 0.45)]


## Summaries of every stored campaign (in parallel); fills `badges`.
func refresh_badges() -> Dictionary:
	var list := local_campaigns()
	var pending := {"n": list.size()}
	for e in list:
		_fetch_badge(e, pending)
	while int(pending["n"]) > 0:
		await get_tree().process_frame
	return badges


func _fetch_badge(e: Dictionary, pending: Dictionary) -> void:
	var r: Dictionary = await api.call_api("GET", "/api/c/%s" % e["id"], null, str(e["token"]), {"timeout": 10, "retries": 1})
	if r["ok"]:
		var sm: Dictionary = CState.normalise(r["data"])
		var b := badge_for(sm)
		badges[str(e["id"])] = {"text": b[0], "color": b[1], "summary": sm}
	elif r["network"]:
		badges[str(e["id"])] = {"text": "Offline", "color": Color(0.7, 0.7, 0.7), "summary": {}}
	elif int(r["status"]) == 401:
		badges[str(e["id"])] = {"text": "Key no longer valid", "color": Color(1.0, 0.6, 0.5), "summary": {}}
	else:
		badges[str(e["id"])] = {"text": "Error", "color": Color(1.0, 0.6, 0.5), "summary": {}}
	pending["n"] = int(pending["n"]) - 1
