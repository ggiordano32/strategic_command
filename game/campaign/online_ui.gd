extends RefCounted
## The campaign screen's online parts (milestone 4): the flow of a turn
## against the server (plan -> Submit turn -> waiting for the ally ->
## resolution -> turn summary -> pending battles), the status in the top
## bar, the waiting panel (Unsubmit, Ping ally, Resolve without the ally
## after the deadline), the online battles list (claims, Wait for ally /
## Take command / Ask ally to join), and the Online dialog (seats, join
## code, device code, Discord, timeout, history and rollback). The screen
## stays the same for local play; `s.online` is null there.

const CData := preload("res://campaign/cdata.gd")
const CState := preload("res://campaign/cstate.gd")
const CRules := preload("res://campaign/crules.gd")
const CTurn := preload("res://campaign/cturn.gd")
const CBattle := preload("res://campaign/cbattle.gd")
const Kit := preload("res://game/campaign/ui_kit.gd")
const NetScript := preload("res://game/net/net.gd")

var s  # the campaign screen
var oc  # game/net/online_campaign.gd
var _busy := false
var _last_state_version := -1
var _focused := false


func _init(screen, p_oc) -> void:
	s = screen
	oc = p_oc
	oc.changed.connect(_on_changed)
	oc.note.connect(_on_note)


func _on_note(text: String, kind: String) -> void:
	if kind == "info":
		s._flash(text)
	else:
		s.show_toast(text)


func _net() -> Node:
	return s.get_node_or_null("/root/Net")


func _name(f: int) -> String:
	return CData.faction_name(f)


func ally_names() -> String:
	var out: Array[String] = []
	for h in oc.st.get("humans", []):
		if int(h) != oc.f:
			out.append(_name(int(h)))
	return " and ".join(out) if not out.is_empty() else "your ally"


func _names(fs: Array) -> String:
	var out: Array[String] = []
	for x in fs:
		out.append(_name(int(x)))
	return " and ".join(out)


func _seat(f: int) -> Dictionary:
	for seat in oc.summary.get("seats", []):
		if int(seat["f"]) == f:
			return seat
	return {}


func _missing_names() -> String:
	var out: Array[String] = []
	for f in oc.summary.get("missing", []):
		if int(f) != oc.f:
			out.append(_name(int(f)))
	return " and ".join(out) if not out.is_empty() else ally_names()


# ------------------------------------------------------------------ flow ---

func _on_changed(what: String) -> void:
	if not is_instance_valid(s) or not s.is_inside_tree():
		return
	if what == "state" or what == "session":
		if s.battle != null or s._resolver != null:
			s.set_meta("refresh_after_battle", true)
			return
		var new_version: bool = int(oc.version) != _last_state_version
		_last_state_version = int(oc.version)
		s.st = oc.st
		if what == "session" and s.f >= 0 and str(oc.st.get("phase", "")) == "plan" and s.orders.is_empty():
			s.orders = oc.plan_orders()
		if new_version or s.st.is_empty() or s.f < 0:
			step()
		else:
			s._replan()
		return
	refresh_status()
	if s.dialog_kind == "online_battles" and s.dialog_open():
		show_battles()
	elif s.dialog_kind == "connecting" and not oc.st.is_empty():
		step()
	elif oc.refused != "" and s.dialog_kind != "refused":
		step()


## What happens next (the online version of the screen's _next_step).
func step() -> void:
	if s.dialog_kind in ["online_battles", "connecting", "waiting", "refused", ""]:
		s.close_dialog()
	if oc.refused != "":
		var box := Kit.vbox(8)
		box.add_child(Kit.label(oc.refused, Kit.FONT, Kit.COL_BAD, true))
		s.show_dialog("Cannot open this campaign", box, [["Main menu", func(): s.request_exit()]], 520)
		s.dialog_kind = "refused"
		return
	if oc.st.is_empty():
		var box2 := Kit.vbox(8)
		box2.add_child(Kit.label("Connecting to the server..." if not oc.offline else "The server cannot be reached and this device has no copy of the campaign yet. Check the connection.", Kit.FONT, Color.WHITE, true))
		s.show_dialog("Online campaign", box2, [["Main menu", func(): s.request_exit()]], 480)
		s.dialog_kind = "connecting"
		return
	s.st = oc.st
	var st: Dictionary = s.st
	if str(st["phase"]) == "over":
		s.f = -1
		s._refresh()
		s.panels.show_game_over()
		refresh_status()
		return
	var turn := int(st["turn"])
	if not _focused:
		_focused = true
		s.f = oc.f
		s._focus_faction()
	var first_look: bool = oc.seen_turn() < turn and turn > 0
	s._set_planner(oc.f, false)
	if str(st["phase"]) == "battles":
		var then := func(): show_battles()
		var auto_bid := _auto_battle()
		if auto_bid >= 0:
			then = func(): s.auto_resolve(auto_bid)
		if first_look:
			var seen: int = oc.seen_turn()
			oc.set_seen(turn)
			s.panels.show_summary(seen, then)
		elif s.dialog_kind != "busy":
			then.call()
	else:
		if oc.seen_turn() < turn:
			var seen2: int = oc.seen_turn()
			oc.set_seen(turn)
			if turn > 0 or not (st["events"] as Array).is_empty():
				s.panels.show_summary(seen2)
			else:
				s.panels.show_intro()
			s._focus_faction()
		s._plan_start_ms = Time.get_ticks_msec()
	refresh_status()
	_warn_rules()


## Setting "battles: always auto": this seat's own unclaimed battle to
## auto-resolve at once (-1 if none).
func _auto_battle() -> int:
	if str(oc.st.get("settings", {}).get("autoresolve", "ask")) != "auto":
		return -1
	for b in CTurn.pending_for(oc.st, oc.f):
		var hs: Array = CRules.battle_humans(oc.st, b)
		var info: Dictionary = oc.battle_info(int(b["id"]))
		if hs.size() == 1 and not (info.get("claim") is Dictionary) and not oc.pending_upload(int(b["id"])):
			return int(b["id"])
	return -1


func _warn_rules() -> void:
	var last: Dictionary = oc.summary.get("last", {})
	var r := str(last.get("rules", ""))
	if r != "" and r != "unknown" and oc.rules != "unknown" and r != oc.rules and not s.has_meta("rules_warned_%d" % oc.version):
		s.set_meta("rules_warned_%d" % oc.version, true)
		s.show_toast("The latest turn was resolved by a different game build (rules %s, yours %s). Reload the page on both devices to get the same version." % [r, oc.rules])


# ---------------------------------------------------------- top status ---

func status_text() -> Array:
	if oc.refused != "":
		return ["Online: error", Kit.COL_BAD]
	if oc.offline:
		return ["Offline", Kit.COL_BAD]
	if oc.summary.is_empty():
		return ["Connecting", Kit.COL_DIM]
	var sm: Dictionary = CState.normalise(oc.summary)
	sm["me"] = oc.f
	var b := NetScript.badge_for(sm)
	if not oc.outbox.is_empty():
		return ["Sending", Kit.COL_GOLD]
	# Short words: the top bar is narrow on a phone (details: tap it).
	var t := str(b[0])
	if t.begins_with("Waiting for your ally"):
		t = "Ally not joined"
	elif t.begins_with("Waiting"):
		t = "Waiting"
	elif t.contains("pending"):
		t = "Battles"
	return [t, b[1]]


func refresh_status() -> void:
	var t := status_text()
	s.net_button.text = str(t[0])
	s.net_button.add_theme_color_override("font_color", t[1])
	s._refresh_top()
	_refresh_wait_panel()


## End / Submit button state for the top refresh.
func end_button_state() -> Array:
	var st: Dictionary = s.st
	if st.is_empty() or str(st.get("phase", "")) != "plan":
		return ["Submit turn", true]
	if oc.i_submitted():
		return ["Submitted", true]
	return ["Submit turn", false]


# ---------------------------------------------------------- waiting panel ---

func _refresh_wait_panel() -> void:
	var p: PanelContainer = s.wait_panel
	for c in p.get_children():
		c.queue_free()
	var st: Dictionary = s.st
	if st.is_empty() or str(st.get("phase", "")) != "plan" or not oc.i_submitted():
		p.visible = false
		return
	var v := Kit.vbox(6)
	p.add_child(v)
	var all_in := bool(oc.summary.get("all_in", false))
	var text := "Resolving the turn..." if all_in else "Submitted. Waiting for %s." % _missing_names()
	if not all_in:
		var lines: Array[String] = []
		for f in oc.summary.get("missing", []):
			var seat := _seat(int(f))
			if not seat.is_empty():
				lines.append("%s %s" % [_name(int(f)), "is online now" if bool(seat.get("online", false)) else _ago(int(seat.get("last_seen", 0)))])
		if not lines.is_empty():
			text += " " + ", ".join(lines) + "."
		var dl := int(oc.summary.get("deadline", 0))
		if dl > 0:
			if bool(oc.summary.get("deadline_expired", false)):
				text += " The turn deadline has passed."
			else:
				text += " Deadline in %s." % _left(dl)
	var l := Kit.label(text, Kit.FONT_SMALL, Color.WHITE, true)
	l.custom_minimum_size.x = 260
	v.add_child(l)
	if not all_in:
		var h := Kit.flow(6)
		var ub := Kit.button("Unsubmit", func(): _unsubmit(), 0, Kit.FONT_SMALL)
		ub.name = "net_unsubmit"
		h.add_child(ub)
		var pb := Kit.button("Ping " + _missing_names(), func(): _ping(-1), 0, Kit.FONT_SMALL)
		pb.name = "net_ping"
		h.add_child(pb)
		if bool(oc.summary.get("deadline_expired", false)):
			var fb := Kit.button("Resolve without " + _missing_names(), func(): _force(), 0, Kit.FONT_SMALL)
			fb.name = "net_force"
			h.add_child(fb)
		v.add_child(h)
	p.visible = true
	p.reset_size()
	_place_wait_panel.call_deferred()


func _place_wait_panel() -> void:
	var p: PanelContainer = s.wait_panel
	if not is_instance_valid(p):
		return
	p.reset_size()
	var vp: Vector2 = s._vp()
	p.position = Vector2(vp.x - p.size.x - 8, vp.y - p.size.y - 64)


func _ago(t_ms: int) -> String:
	if t_ms <= 0:
		return "has not been here yet"
	var now := int(oc.summary.get("server_time", Time.get_unix_time_from_system() * 1000.0))
	var m := maxi((now - t_ms) / 60000, 0)
	if m < 2:
		return "was here a minute ago"
	if m < 120:
		return "was here %d min ago" % m
	if m < 48 * 60:
		return "was here %d h ago" % (m / 60)
	return "was here %d days ago" % (m / 1440)


func _left(dl: int) -> String:
	var now := int(oc.summary.get("server_time", Time.get_unix_time_from_system() * 1000.0))
	var m := maxi((dl - now) / 60000, 0)
	if m < 120:
		return "%d min" % m
	return "%d h" % (m / 60)


# ---------------------------------------------------------------- actions ---

func submit(orders: Array) -> void:
	if _busy:
		return
	_busy = true
	s.end_button.disabled = true
	s.end_button.text = "Sending..."
	var r: Dictionary = await oc.submit(orders)
	_busy = false
	if not r["ok"]:
		if r["network"]:
			s.show_toast("Could not reach the server: the turn is not submitted yet. Your plan is kept; try again when the connection is back.")
		elif str(r["error"]) == "conflict":
			s.show_toast("The campaign moved on while you planned (%s). Your plan is kept where it still applies." % str(r["message"]))
		else:
			s.show_toast("The server refused the turn: %s" % str(r["message"]))
	else:
		s._t("online_submit_ui", {"turn": int(s.st["turn"]), "orders": orders.size()})
	refresh_status()


func _unsubmit() -> void:
	var r: Dictionary = await oc.unsubmit()
	if not r["ok"]:
		s.show_toast("Could not unsubmit: %s" % str(r["message"] if r["message"] != "" else r["error"]))
	else:
		s.orders = oc.plan_orders()
		var sub = oc.session.get("submitted", {})
		if sub is Dictionary and int(sub.get("turn", -1)) == int(s.st["turn"]):
			s.orders = (sub["orders"] as Array).duplicate(true)
		s._replan()
	refresh_status()


func _ping(bid: int) -> void:
	var r: Dictionary = await oc.ping(bid)
	if r["ok"]:
		s._flash("Sent." if bool(r["data"].get("sent", false)) else "Already pinged a moment ago.")
		if not bool(r["data"].get("sent", false)) or str(oc.summary.get("webhook", "")) == "":
			if str(oc.summary.get("webhook", "")) == "":
				s.show_toast("No Discord webhook is set for this campaign, so nobody was notified. Set one in Online.")
	else:
		s.show_toast("Could not ping: %s" % str(r["message"]))


func _force() -> void:
	var res: String = await oc.resolve_now(true)
	if res not in ["ok", "already", "lost"]:
		s.show_toast("Could not resolve the turn (%s)." % res)


# --------------------------------------------------------------- battles ---

func show_battles() -> void:
	var st: Dictionary = s.st
	var list := CTurn.pending_for(st)
	var box := Kit.vbox(10)
	if list.is_empty():
		box.add_child(Kit.label("No battles pending.", Kit.FONT, Color.WHITE))
		s.show_dialog("Battles", box, [["Close", Callable()]], 520)
		return
	box.add_child(Kit.label("Battles must be resolved before the next turn. Your own: auto-resolve or fight. Where your ally's army fights too: fight together live (your ally is asked to join and commands their own army), wait for them (they are pinged), or take command of their army (they are told).", Kit.FONT_SMALL, Kit.COL_DIM, true))
	for b in list:
		box.add_child(_battle_card(st, b))
	s.show_dialog("Pending battles (%d)" % list.size(), box, [["Close", Callable()]], 720)
	s.dialog_kind = "online_battles"


func _battle_card(st: Dictionary, b: Dictionary) -> Control:
	var card: Control = s.panels._battle_card(st, b)
	var v: VBoxContainer = card.get_child(0)
	var h: HBoxContainer = v.get_child(v.get_child_count() - 1)
	for c in h.get_children():
		h.remove_child(c)
		c.queue_free()
	var bid := int(b["id"])
	var info: Dictionary = oc.battle_info(bid)
	var humans: Array = CRules.battle_humans(st, b)
	var others: Array = []
	for x in humans:
		if int(x) != oc.f:
			others.append(int(x))
	var cl = info.get("claim")
	var cmd := int(info.get("command_by", -1))
	var wait_by := int(info.get("wait_by", -1))
	var live = info.get("live")
	var live_ok: bool = oc.live_ok() and not others.is_empty() and humans.has(oc.f)
	var status := ""
	var col := Kit.COL_DIM
	if live is Dictionary and live_ok and not oc.pending_upload(bid):
		return _live_card(card, v, h, bid, live, others)
	if oc.pending_upload(bid):
		status = "Your result is saved on this device and being sent."
		col = Kit.COL_GOLD
	elif cl is Dictionary and not bool(cl.get("mine", false)):
		status = "%s is %s this battle now." % [_name(int(cl["f"])) if int(cl["f"]) != oc.f else "Your other device",
			"fighting" if str(cl.get("mode", "")) in ["fight", "live"] else "auto-resolving"]
		col = Kit.COL_GOLD
	elif not others.is_empty() and cmd != oc.f:
		var mine := humans.has(oc.f)
		status = "%s's army is in this battle%s." % [_names(others), " with yours" if mine else ""]
		var seat := _seat(int(others[0]))
		status += " %s %s." % [_name(int(others[0])), "is online now" if bool(seat.get("online", false)) else _ago(int(seat.get("last_seen", 0)))]
		if wait_by >= 0:
			status += " %s chose to wait for them." % ("You" if wait_by == oc.f else _name(wait_by))
		if cmd >= 0:
			status += " %s took command." % _name(cmd)
	elif cmd == oc.f and not others.is_empty():
		status = "You command %s's army here." % _names(others)
	if status != "":
		v.add_child(Kit.label(status, Kit.FONT_SMALL, col, true))
	h.alignment = BoxContainer.ALIGNMENT_END
	var busy: bool = oc.pending_upload(bid) or (cl is Dictionary and not bool(cl.get("mine", false)))
	if busy:
		v.move_child(h, v.get_child_count() - 1)
		return card
	if others.is_empty() or cmd == oc.f:
		var ab := Kit.button("Auto-resolve", func(): s.auto_resolve(bid), 130)
		ab.name = "auto_%d" % bid
		h.add_child(ab)
		# With the ally's army in it the battle is fought live: they can
		# join at any time and command their own army.
		var fb := Kit.button("Fight", func():
			if live_ok:
				s.fight_live(bid, true)
			else:
				s.fight(bid), 100)
		fb.name = "fight_%d" % bid
		h.add_child(fb)
	else:
		var wb := Kit.button("Wait for ally", func(): _choose(bid, "wait"), 0)
		wb.name = "wait_%d" % bid
		h.add_child(wb)
		var tb := Kit.button("Take command", func(): _choose(bid, "command"), 0)
		tb.name = "command_%d" % bid
		h.add_child(tb)
		if live_ok:
			# Opens the live battle's lobby and asks the ally to join (Discord).
			var lb := Kit.button("Fight together", func(): s.fight_live(bid, true), 0)
			lb.name = "together_%d" % bid
			h.add_child(lb)
		else:
			var pb := Kit.button("Ask to join now", func(): _ping(bid), 0)
			pb.name = "ping_%d" % bid
			h.add_child(pb)
	v.move_child(h, v.get_child_count() - 1)
	return card


## A battle being fought live: who is in it, and Join battle.
func _live_card(card: Control, v: VBoxContainer, h: HBoxContainer, bid: int, live: Dictionary, others: Array) -> Control:
	var host := int(live.get("host", -1))
	var ins: Array[String] = []
	var me_in := false
	for p in live.get("players", []):
		if bool(p.get("on", false)):
			if int(p["f"]) == oc.f:
				me_in = true
			else:
				ins.append(_name(int(p["f"])))
	var text := ""
	if str(live.get("state", "")) == "lobby":
		text = "Live now: %s is waiting for you in the battle lobby." % _name(host) if host != oc.f else "Your battle lobby is open."
	else:
		var mins := maxi(0, (int(oc.summary.get("server_time", 0)) - int(live.get("since", 0))) / 60000)
		text = "Live now: %s in battle%s." % [" and ".join(ins) if not ins.is_empty() else "nobody", (" (started %d min ago)" % mins) if mins > 0 else ""]
	if me_in:
		text += " You are in it on another device."
	v.add_child(Kit.label(text, Kit.FONT_SMALL, Kit.COL_GOOD, true))
	h.alignment = BoxContainer.ALIGNMENT_END
	var jb := Kit.button("Join battle", func(): s.fight_live(bid, false), 130)
	jb.name = "join_%d" % bid
	h.add_child(jb)
	if str(live.get("state", "")) != "lobby" and not others.is_empty():
		var kb := Kit.button("Join, %s keeps my army" % _name(host), func(): s.fight_live(bid, false, true), 0, Kit.FONT_SMALL)
		kb.name = "join_keep_%d" % bid
		kb.tooltip_text = "Watch and take gifted units; %s keeps commanding your army." % _name(host)
		if host != oc.f:
			h.add_child(kb)
	v.move_child(h, v.get_child_count() - 1)
	return card


func _choose(bid: int, choice: String) -> void:
	var r: Dictionary = await oc.choose(bid, choice)
	if not r["ok"]:
		s.show_toast("Could not do that: %s" % str(r["message"]))
	elif choice == "wait":
		s._flash("Your ally has been pinged; the battle waits for them.")
	show_battles()


## Claim a battle before fighting or auto-resolving it. Returns true if this
## device now holds it.
func claim(bid: int, mode: String) -> bool:
	var r: Dictionary = await oc.claim(bid, mode)
	if r["ok"]:
		return true
	if r["network"]:
		s.show_toast("Could not reach the server to take this battle. Try again when the connection is back.")
	elif str(r["error"]) == "claimed":
		s.show_toast("%s is already resolving this battle." % _name(int(r["data"].get("held_by", -1))))
	elif str(r["error"]) == "need_command":
		s.show_toast("Your ally's army is in this battle: wait for them, or take command of their army first.")
	else:
		s.show_toast("Cannot take this battle: %s" % str(r["message"]))
	await oc.sync()
	show_battles()
	return false


## A battle outcome: upload it (kept locally until the server confirms).
func upload(bid: int, outcome: Dictionary) -> void:
	var before := (s.st["events"] as Array).size()
	var box := Kit.vbox(8)
	box.add_child(Kit.label("Sending the result to the server...", Kit.FONT, Color.WHITE))
	s.show_dialog("Battle result", box, [])
	s.dialog_kind = "busy"
	var res: String = await oc.upload_battle(bid, outcome)
	s.dialog_kind = ""
	s.st = oc.st
	s._replan()
	if res == "ok":
		s.panels.show_battle_result(before, outcome)
	else:
		var b2 := Kit.vbox(8)
		var msg := "The result is saved on this device and will be sent as soon as the server can be reached. You can close the game; it is sent next time."
		if res == "waiting":
			msg = "Your ally's device is resolving this battle too. Your result is kept and sent if theirs does not arrive."
		elif res not in ["network", "busy"]:
			msg = "The server did not accept the result (%s)." % res
		b2.add_child(Kit.label(msg, Kit.FONT, Color.WHITE, true))
		s.show_dialog("Battle result", b2, [["Continue", func(): step()]], 520)
	refresh_status()


# ----------------------------------------------------------- online menu ---

func show_online() -> void:
	var sm: Dictionary = oc.summary
	var box := Kit.vbox(8)
	var net := _net()
	box.add_child(Kit.label("%s - online co-op. You play %s." % [str(sm.get("name", oc.st.get("name", ""))), _name(oc.f)], Kit.FONT, Kit.COL_GOLD, true))
	if oc.offline:
		box.add_child(Kit.label("The server cannot be reached right now. You can keep planning; it syncs when the connection is back.", Kit.FONT_SMALL, Kit.COL_BAD, true))
	for seat in sm.get("seats", []):
		var f := int(seat["f"])
		var h := Kit.hbox(6)
		h.add_child(Kit.swatch(CData.faction_color(f), 16))
		var t := "%s%s: " % [_name(f), " (you)" if f == oc.f else ""]
		if not bool(seat.get("claimed", false)):
			t += "seat open, waiting for the ally to join"
		else:
			t += "online now" if bool(seat.get("online", false)) else _ago(int(seat.get("last_seen", 0))).trim_prefix("was ")
			if str(sm.get("phase", "")) == "plan":
				t += ", submitted" if bool(seat.get("submitted", false)) else ", planning"
		h.add_child(Kit.label(t, Kit.FONT_SMALL, Color.WHITE, true))
		box.add_child(h)
	if str(sm.get("join_code", "")) != "":
		var code := str(sm["join_code"])
		box.add_child(Kit.section("Invite your ally"))
		box.add_child(Kit.label("Join code %s, or send this link: %s" % [NetScript.show_code(code), net.join_link(code) if net else ""], Kit.FONT, Color.WHITE, true))
		var cb := Kit.button("Copy link", func():
			DisplayServer.clipboard_set(net.join_link(code) if net else code)
			s._flash("Copied."), 0)
		box.add_child(cb)
	box.add_child(Kit.section("Play on another device"))
	var link_box := Kit.vbox(6)
	link_box.add_child(Kit.label("Get a code to continue this campaign on your desktop or another phone (valid 30 minutes; this device keeps working too).", Kit.FONT_SMALL, Kit.COL_DIM, true))
	var lb := Kit.button("Get a device code", func(): _make_link(link_box), 0)
	lb.name = "net_device_code"
	link_box.add_child(lb)
	box.add_child(link_box)
	box.add_child(Kit.section("Discord notifications"))
	var hook_l := "Webhook: " + (str(sm.get("webhook", "")) if str(sm.get("webhook", "")) != "" else "not set")
	box.add_child(Kit.label(hook_l, Kit.FONT_SMALL, Kit.COL_DIM, true))
	var hook_edit := LineEdit.new()
	hook_edit.placeholder_text = "https://discord.com/api/webhooks/..."
	hook_edit.custom_minimum_size = Vector2(300, 40)
	hook_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(hook_edit)
	var user_edit := LineEdit.new()
	user_edit.placeholder_text = "Your Discord user id (for @mentions, optional)"
	user_edit.custom_minimum_size = Vector2(300, 40)
	user_edit.text = str(net.accounts.data.get("discord_user", "")) if net else ""
	box.add_child(user_edit)
	var dh := Kit.flow(6)
	dh.add_child(Kit.button("Save", func(): _save_discord(hook_edit.text.strip_edges(), user_edit.text.strip_edges()), 0))
	dh.add_child(Kit.button("Send test message", func(): _test_notify(), 0))
	if str(sm.get("webhook", "")) != "":
		dh.add_child(Kit.button("Remove webhook", func(): _save_discord("-", user_edit.text.strip_edges()), 0))
	box.add_child(dh)
	var tmo := int(sm.get("timeout_h", 0))
	var tb := Kit.button("Turn timeout: " + ("off" if tmo == 0 else "%d h" % tmo), func(): _cycle_timeout(tmo), 0)
	tb.tooltip_text = "After the first player submits, the other has this long; then the waiting player may resolve the turn without them."
	box.add_child(tb)
	box.add_child(Kit.section("Safety"))
	var vt := Kit.button("Check results on this device: " + ("on" if oc.verify_enabled else "off"), func():
		oc.verify_enabled = not oc.verify_enabled
		show_online(), 0)
	vt.tooltip_text = "Re-runs your ally's turn resolutions here and warns if this device gets a different result."
	box.add_child(vt)
	box.add_child(Kit.button("History and rollback", func(): show_history(), 0))
	box.add_child(Kit.label("Version %d, state %s, rules %s." % [oc.version, oc.state_hash, oc.rules], Kit.FONT_SMALL, Kit.COL_DIM))
	s.show_dialog("Online", box, [["Close", Callable()]], 620)
	s.dialog_kind = "online_menu"


func _make_link(box: VBoxContainer) -> void:
	var r: Dictionary = await oc.make_link()
	if not r["ok"]:
		s.show_toast("Could not get a code: %s" % str(r["message"] if r["message"] != "" else r["error"]))
		return
	var code := str(r["data"]["code"])
	var net := _net()
	var link: String = net.device_link(code) if net else code
	for c in box.get_children():
		c.queue_free()
	box.add_child(Kit.label("On the other device open the game and enter this code under Join, or open the link:", Kit.FONT_SMALL, Color.WHITE, true))
	var cl := Kit.label(NetScript.show_code(code), 26, Kit.COL_GOLD)
	cl.name = "device_code"
	box.add_child(cl)
	box.add_child(Kit.label(link, Kit.FONT_SMALL, Kit.COL_DIM, true))
	box.add_child(Kit.button("Copy link", func():
		DisplayServer.clipboard_set(link)
		s._flash("Copied."), 0))
	s._t("online_device_code", {})


func _save_discord(hook: String, user: String) -> void:
	var body := {"discord_user": user}
	if hook == "-":
		body["webhook_url"] = ""
	elif hook != "":
		body["webhook_url"] = hook
	var net := _net()
	if net:
		net.accounts.set_value("discord_user", user)
	var r: Dictionary = await oc.settings(body)
	if r["ok"]:
		s._flash("Saved.")
	else:
		s.show_toast(str(r["message"]) if str(r["message"]) != "" else "Could not save (%s)." % r["error"])
	show_online()


func _test_notify() -> void:
	var r: Dictionary = await oc.test_notify()
	s.show_toast("Test message sent: check Discord." if r["ok"] else (str(r["message"]) if str(r["message"]) != "" else "Failed: %s" % r["error"]))


func _cycle_timeout(cur: int) -> void:
	var ch := [0, 12, 24, 48, 72]
	var nxt: int = ch[(ch.find(cur) + 1) % ch.size()]
	await oc.settings({"turn_timeout_h": nxt})
	show_online()


func show_history() -> void:
	var box := Kit.vbox(6)
	box.add_child(Kit.label("Loading...", Kit.FONT, Color.WHITE))
	s.show_dialog("History", box, [["Back", func(): show_online()]], 620)
	var r: Dictionary = await oc.history()
	for c in box.get_children():
		c.queue_free()
	if not r["ok"]:
		box.add_child(Kit.label("Could not load the history.", Kit.FONT, Kit.COL_BAD))
		return
	var vs: Array = r["data"]["versions"]
	box.add_child(Kit.label("Every version of the campaign is kept (%d, %d KB). Rolling back makes an old version the current one again (as a new version, so nothing is lost); use it only if a bug broke the campaign. Both players should agree." % [
		vs.size(), int(r["data"]["stored_bytes"]) / 1024], Kit.FONT_SMALL, Kit.COL_DIM, true))
	var start := maxi(0, vs.size() - 12)
	for i in range(vs.size() - 1, start - 1, -1):
		var v: Dictionary = vs[i]
		var h := Kit.hbox(6)
		var by := int(v["by"])
		var t := "v%d  turn %d  %s%s" % [int(v["version"]), int(v["turn"]) + 1, str(v["kind"]), (" by " + _name(by)) if by >= 0 else ""]
		var l := Kit.label(t, Kit.FONT_SMALL, Color.WHITE if int(v["version"]) != oc.version else Kit.COL_GOLD)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(l)
		if int(v["version"]) < oc.version:
			var vv := int(v["version"])
			var rb := Kit.button("Roll back here", Callable(), 0, Kit.FONT_SMALL)
			rb.pressed.connect(func():
				if rb.text == "Sure? Tap again":
					_rollback(vv)
				else:
					rb.text = "Sure? Tap again")
			h.add_child(rb)
		box.add_child(h)
	s.call_deferred("_center_dialog")


func _rollback(v: int) -> void:
	var r: Dictionary = await oc.rollback(v)
	if r["ok"]:
		s._t("online_rollback", {"to": v})
		s.show_toast("Rolled back to version %d." % v)
	else:
		s.show_toast("Rollback failed: %s" % str(r["message"]))
