extends Control
## Custom battle screen (start screen > Custom battle): the map, the two
## sides' armies (units from the whole roster, all tiers and faction
## elites, with campaign prices and an optional equal budget), who
## commands each army (Player 1, Player 2, the AI at a skill and
## personality per side), the deployment time; a template from the
## sandbox's battles and test matchups. Play solo starts at once; Play
## online creates a custom battle room (docs/SERVER.md section 18) and
## shows its code; Join takes a friend's code. In the online lobby the host
## owns the setup, Player 2 may only change the units of Player 2's
## armies; both press Ready, the host starts, and the battle opens with
## the live session (co-op on one side or head-to-head).

signal back
signal play_solo(built: Dictionary, setup: Dictionary)
signal play_online(session: Node, setup: Dictionary)

const CS := preload("res://game/custom/custom_setup.gd")
const Kit := preload("res://game/campaign/ui_kit.gd")
const TouchScroll := preload("res://game/touch_scroll.gd")
const UT := preload("res://sim/unit_types.gd")
const Terrain := preload("res://sim/terrain.gd")
const MapGen := preload("res://sim/mapgen.gd")
const CoopSession := preload("res://game/net/coop_session.gd")
const NetScript := preload("res://game/net/net.gd")

const SKILL_NAMES := ["Easy", "Average", "Skilled"]
const STYLE_NAMES := ["Cautious", "Balanced", "Aggressive"]
const SIDE_NAMES := ["Side 1 (bottom)", "Side 2 (top)"]
const PLAYER_COLORS := [Color(0.35, 0.65, 1.0), Color(1.0, 0.55, 0.3)]

var setup: Dictionary = {}
var session = null            ## CoopSession while online (lobby, then the battle)
var _tmpl := -1
var _box: VBoxContainer
var _info: Label
var _code_edit: LineEdit
var _picker: PanelContainer
var _pick_target := [-1, -1]
var _busy := false
var _started := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.12, 0.15, 0.12)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var scroll := TouchScroll.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.offset_left = 12
	scroll.offset_right = -12
	scroll.offset_top = 8
	scroll.offset_bottom = -8
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	_box = Kit.vbox(8)
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_box)
	if setup.is_empty():
		setup = CS.default_setup(int(Time.get_unix_time_from_system()) % 100000)
	_build_picker()
	_rebuild()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--custom-template="):
			_load_template(CS.TEMPLATES.find(a.get_slice("=", 1)))  # testing aid
		elif a.begins_with("--custom-join="):
			_code_edit.text = a.get_slice("=", 1)  # testing aid
			_join.call_deferred()


func _net() -> Node:
	return get_node_or_null("/root/Net")


func _me() -> int:
	return session.me if session != null else 0


func _can_edit_all() -> bool:
	return session == null or (session.me == 0 and not _started)


func _can_edit_army(s: int, a: int) -> bool:
	if session == null:
		return true
	if _started:
		return false
	return session.me == 0 or str(setup["sides"][s]["armies"][a]["ctrl"]) == "p2"


## The setup changed here: online, it goes to the relay (and comes back).
func _changed() -> void:
	if session != null:
		session.send_setup(setup)
	_rebuild()


# ---------------------------------------------------------------- build ---

func _rebuild() -> void:
	for c in _box.get_children():
		c.queue_free()
	var head := Kit.flow(8)
	head.add_child(Kit.label("Custom battle", 22, Kit.COL_GOLD))
	if _can_edit_all():
		var tb := Kit.button("Template: " + (CS.template_title(CS.TEMPLATES[_tmpl]) if _tmpl >= 0 else "your own"),
			func(): _load_template((_tmpl + 1) % CS.TEMPLATES.size()), 0, 14)
		tb.name = "custom_template"
		head.add_child(tb)
	head.add_child(Kit.button("Back", _back, 80))
	if session == null:
		var ps := Kit.icon_button("Play solo", "battles", _play_solo, 120, 17)
		ps.name = "custom_play_solo"
		head.add_child(ps)
		var po := Kit.icon_button("Play online", "online", _create_online, 130, 17)
		po.name = "custom_play_online"
		head.add_child(po)
	_box.add_child(head)
	if session == null:
		var jr := Kit.flow(8)
		jr.add_child(Kit.label("A friend's code:", Kit.FONT, Kit.COL_DIM))
		_code_edit = Kit.text_field("ABC-DEF", "", 150, "Your friend's code", true)
		_code_edit.name = "custom_code"
		jr.add_child(Kit.field_box(_code_edit))
		var jb := Kit.icon_button("Join", "online", _join, 80)
		jb.name = "custom_join"
		jr.add_child(jb)
		_box.add_child(jr)
	else:
		_box.add_child(_lobby_view())
	_info = Kit.label("", Kit.FONT, Kit.COL_DIM, true)
	_box.add_child(_info)
	_box.add_child(_map_row())
	var sides := HBoxContainer.new()
	sides.add_theme_constant_override("separation", 10)
	sides.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for s in 2:
		sides.add_child(_side_view(s))
	_box.add_child(sides)
	_show_check()


func _show_check() -> void:
	if _info == null:
		return
	var why := CS.check(setup, session != null)
	if why != "":
		_info.text = why
		_info.add_theme_color_override("font_color", Kit.COL_BAD)
	else:
		var p2 := CS.side_of_player(setup, 1)
		var p1 := CS.side_of_player(setup, 0)
		var mode := "solo (Player 2's armies are fought by the AI)" if p2 >= 0 else "solo"
		if p2 >= 0:
			mode += "; online: " + ("co-op, Player 1 and Player 2 on one side" if p1 == p2 else "head-to-head")
		_info.text = "Ready to play %s." % mode if session == null else "The setup is complete."
		_info.add_theme_color_override("font_color", Kit.COL_GOOD)


func _map_row() -> Control:
	var mp: Dictionary = setup["map"]
	var v := Kit.vbox(6)
	var row := Kit.flow(8)
	var ed := _can_edit_all()
	var field := str(mp["kind"]) == "field"
	row.add_child(_opt("Map: " + ("Field" if field else "Settlement"), func():
		mp["kind"] = "settlement" if field else "field"
		_changed(), ed))
	if field:
		row.add_child(_opt("Terrain: " + Terrain.KIND_NAMES[int(mp["terrain"])], func():
			mp["terrain"] = CS.FIELD_KINDS[(CS.FIELD_KINDS.find(int(mp["terrain"])) + 1) % CS.FIELD_KINDS.size()]
			_changed(), ed))
	else:
		row.add_child(_opt("Plan: " + MapGen.PLAN_NAMES[int(mp["plan"])], func():
			mp["plan"] = (int(mp["plan"]) + 1) % (MapGen.PLAN_RING + 1)
			_changed(), ed))
		row.add_child(_opt("Site: " + Terrain.KIND_NAMES[int(mp["terrain"])], func():
			mp["terrain"] = CS.SITE_KINDS[(CS.SITE_KINDS.find(int(mp["terrain"])) + 1) % CS.SITE_KINDS.size()]
			_changed(), ed))
		row.add_child(_opt(["Village", "Town", "City"][int(mp["level"])], func():
			mp["level"] = (int(mp["level"]) + 1) % 3
			_changed(), ed))
		row.add_child(_opt("Walls %d" % int(mp["walls"]), func():
			mp["walls"] = (int(mp["walls"]) + 1) % 4
			_changed(), ed))
		row.add_child(_opt("Coast" if int(mp["coast"]) != 0 else "Inland", func():
			mp["coast"] = 1 - int(mp["coast"])
			_changed(), ed))
		row.add_child(_opt("%s defends" % SIDE_NAMES[int(mp["def"])].get_slice(" (", 0), func():
			mp["def"] = 1 - int(mp["def"])
			_changed(), ed))
		if int(mp["walls"]) > 0:
			# The attackers' siege equipment (a siege of a turn: ladders, of two: a ram too).
			var lb := _opt("Ladders: " + ("yes" if int(mp.get("ladders", 0)) != 0 else "no"), func():
				mp["ladders"] = 1 - int(mp.get("ladders", 0))
				_changed(), ed)
			lb.name = "custom_ladders"
			lb.tooltip_text = "The attackers' foot carry ladders: tap a stretch of wall with one selected to climb it"
			row.add_child(lb)
			var rb := _opt("Ram: " + ("yes" if int(mp.get("ram", 0)) != 0 else "no"), func():
				mp["ram"] = 1 - int(mp.get("ram", 0))
				_changed(), ed)
			rb.name = "custom_ram"
			rb.tooltip_text = "The attackers bring a battering ram: tap a gate with it selected to batter it"
			row.add_child(rb)
	row.add_child(_opt("Ground: " + MapGen.PALETTE_NAMES[int(mp["ground"])], func():
		mp["ground"] = (int(mp["ground"]) + 1) % MapGen.PALETTE_NAMES.size()
		_changed(), ed))
	row.add_child(_opt("Woods: %d%%" % int(mp["woods"]), func():
		mp["woods"] = [0, 15, 30, 50][([0, 15, 30, 50].find(int(mp["woods"])) + 1) % 4]
		_changed(), ed))
	var se := Kit.text_field("seed", str(int(mp["mseed"])), 100, "Map seed", true)
	se.tooltip_text = "Map seed: the same seed and settings always give the same ground"
	se.editable = ed
	se.text_submitted.connect(func(t: String):
		mp["mseed"] = absi(int(t)) if t.is_valid_int() else absi(t.hash())
		_changed())
	se.focus_exited.connect(func():
		var t := se.text
		var nv := absi(int(t)) if t.is_valid_int() else absi(t.hash())
		if nv != int(mp["mseed"]):
			mp["mseed"] = nv
			_changed())
	row.add_child(Kit.label("Seed", Kit.FONT_SMALL, Kit.COL_DIM))
	row.add_child(se)
	v.add_child(row)
	var r2 := Kit.flow(8)
	var dt := int(setup.get("deploy", 60))
	var db := _opt("Deployment: " + ({0: "none", 60: "1 min", 120: "2 min"}[dt] if dt in [0, 60, 120] else "%d s" % dt), func():
		setup["deploy"] = CS.DEPLOY_CHOICES[(CS.DEPLOY_CHOICES.find(dt) + 1) % CS.DEPLOY_CHOICES.size()]
		_changed(), ed)
	db.name = "custom_deploy"
	r2.add_child(db)
	var tl := int(setup.get("time", 900))
	var tlb := _opt("Battle time: %d min" % (tl / 60), func():
		setup["time"] = CS.TIME_CHOICES[(CS.TIME_CHOICES.find(tl) + 1) % CS.TIME_CHOICES.size()]
		_changed(), ed)
	tlb.name = "custom_time"
	r2.add_child(tlb)
	var fi := int(setup.get("funds", 0))
	r2.add_child(_opt("Funds per side: " + CS.FUNDS_NAMES[fi], func():
		setup["funds"] = (fi + 1) % CS.FUNDS.size()
		_changed(), ed))
	v.add_child(r2)
	return v


func _side_view(s: int) -> Control:
	var sd: Dictionary = setup["sides"][s]
	var p := Kit.panel(Color(0.08, 0.1, 0.12, 0.9), 8)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := Kit.vbox(6)
	p.add_child(v)
	var cost := CS.side_cost(setup, s)
	var budget: int = CS.FUNDS[int(setup.get("funds", 0))]
	var h := Kit.flow(6)
	h.add_child(Kit.label(SIDE_NAMES[s], Kit.FONT_TITLE, Color(0.55, 0.75, 1.0) if s == 0 else Color(1.0, 0.6, 0.5)))
	h.add_child(Kit.label(("%d / %d" % [cost, budget]) if budget > 0 else "cost %d" % cost, Kit.FONT_SMALL,
		Kit.COL_BAD if budget > 0 and cost > budget else Kit.COL_DIM))
	v.add_child(h)
	var players := CS.side_players(setup, s)
	var has_ai := false
	for a in sd["armies"]:
		if str(a["ctrl"]) == "ai":
			has_ai = true
	if has_ai:
		var ar := Kit.flow(6)
		if players.is_empty():
			ar.add_child(_opt("AI: " + SKILL_NAMES[int(sd["skill"])], func():
				sd["skill"] = (int(sd["skill"]) + 1) % 3
				_changed(), _can_edit_all()))
			ar.add_child(_opt(STYLE_NAMES[int(sd["style"])], func():
				sd["style"] = (int(sd["style"]) + 1) % 3
				_changed(), _can_edit_all()))
		else:
			ar.add_child(Kit.label("AI armies on a side with a player are commanded by that player.", Kit.FONT_SMALL, Kit.COL_DIM, true))
		v.add_child(ar)
	for ai in (sd["armies"] as Array).size():
		v.add_child(_army_view(s, ai))
	if (sd["armies"] as Array).size() < CS.MAX_ARMIES and _can_edit_all():
		var ab := Kit.button("+ Add army", func():
			(sd["armies"] as Array).append({"ctrl": "ai" if s == 1 else "p1", "units": []})
			_changed(), 0, 14)
		ab.name = "custom_add_army_%d" % s
		v.add_child(ab)
	return p


func _army_view(s: int, ai: int) -> Control:
	var army: Dictionary = setup["sides"][s]["armies"][ai]
	var v := Kit.vbox(4)
	var h := Kit.flow(6)
	h.add_child(Kit.label("Army %d" % (ai + 1), Kit.FONT, Color.WHITE))
	var ctrl := str(army["ctrl"])
	var cb := _opt(CS.CTRL_NAMES[ctrl], func():
		army["ctrl"] = {"p1": "p2", "p2": "ai", "ai": "p1"}[ctrl]
		_changed(), _can_edit_all())
	cb.name = "custom_ctrl_%d_%d" % [s, ai]
	if ctrl != "ai":
		cb.add_theme_color_override("font_color", PLAYER_COLORS[0 if ctrl == "p1" else 1])
	h.add_child(cb)
	if _can_edit_all() and (setup["sides"][s]["armies"] as Array).size() > 1:
		h.add_child(Kit.icon_button("Remove", "cancel", func():
			(setup["sides"][s]["armies"] as Array).remove_at(ai)
			_changed(), 0, 13))
	v.add_child(h)
	var units: Array = army["units"]
	var ed := _can_edit_army(s, ai)
	for k in units.size():
		var e: Array = units[k]
		var ty := UT.index_of(str(e[0]))
		var r := Kit.hbox(4)
		var nm := Kit.label("%s  %d" % [UT.text(ty, "name") if ty >= 0 else str(e[0]), int(e[1])], Kit.FONT_SMALL, Color.WHITE)
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		r.add_child(nm)
		r.add_child(Kit.label(str(CS.unit_cost(str(e[0]), int(e[1]))), Kit.FONT_SMALL, Kit.COL_DIM))
		if ed:
			r.add_child(Kit.button("x", func():
				units.remove_at(k)
				_changed(), 34, 13))
		v.add_child(r)
	if ed and units.size() < CS.MAX_UNITS:
		var add := Kit.button("+ Add unit (%d/%d)" % [units.size(), CS.MAX_UNITS], func(): _open_picker(s, ai), 0, 14)
		add.name = "custom_add_unit_%d_%d" % [s, ai]
		v.add_child(add)
	return v


func _opt(text: String, cb: Callable, enabled: bool = true) -> Button:
	var b := Kit.button(text, cb, 0, 14)
	b.disabled = not enabled
	return b


# --------------------------------------------------------------- picker ---

## The roster: every type by line (all tiers and the factions' elites).
func _build_picker() -> void:
	_picker = Kit.panel(Color(0.05, 0.06, 0.07, 0.97), 10)
	_picker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_picker.offset_left = 20
	_picker.offset_right = -20
	_picker.offset_top = 16
	_picker.offset_bottom = -16
	_picker.visible = false
	add_child(_picker)
	var v := Kit.vbox(6)
	_picker.add_child(v)
	var h := Kit.hbox(8)
	var t := Kit.label("Add a unit (full strength; price in campaign gold)", Kit.FONT_TITLE, Kit.COL_GOLD)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(t)
	h.add_child(Kit.icon_button("Close", "close", func(): _picker.visible = false, 90))
	v.add_child(h)
	var sc := TouchScroll.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(sc)
	var list := Kit.vbox(4)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(list)
	for line in UT.LINES:
		var f := Kit.flow(6)
		f.add_child(Kit.label(str(line).capitalize(), Kit.FONT, Kit.COL_DIM))
		for ty in UT.count():
			if UT.line_of(ty) != line:
				continue
			var key := UT.key_of(ty)
			var b := Kit.button("%s  %d" % [UT.text(ty, "name"), UT.price_of(ty)], func(): _pick(key), 0, 13)
			b.name = "pick_" + key
			f.add_child(b)
		list.add_child(f)


func _open_picker(s: int, ai: int) -> void:
	_pick_target = [s, ai]
	_picker.visible = true


func _pick(key: String) -> void:
	var s: int = _pick_target[0]
	var ai: int = _pick_target[1]
	if s < 0:
		return
	var units: Array = setup["sides"][s]["armies"][ai]["units"]
	if units.size() < CS.MAX_UNITS:
		units.append([key, UT.size_of(UT.index_of(key))])
	if units.size() >= CS.MAX_UNITS:
		_picker.visible = false
	_changed()


func _load_template(i: int) -> void:
	if i < 0:
		return
	_tmpl = i
	setup = CS.template(CS.TEMPLATES[i], int(setup.get("seed", 1)))
	_changed()


# --------------------------------------------------------------- playing ---

func _play_solo() -> void:
	var b := CS.build(setup, true)
	if b.has("error"):
		_info.text = str(b["error"])
		return
	play_solo.emit(b, setup.duplicate(true))


func _back() -> void:
	if session != null:
		session.leave()
		session.queue_free()
		session = null
		_started = false
		_rebuild()
		return
	back.emit()


func _create_online() -> void:
	var why := CS.check(setup, true)
	if why != "":
		_info.text = why
		return
	var net := _net()
	if net == null or not net.has_server():
		_info.text = "Online play needs the game server: open the game from its web address."
		return
	if not net.available and not await net.check_server():
		_info.text = "The game server is not available right now."
		return
	if int(net.info.get("api", 0)) < 3:
		_info.text = "The game server is too old for custom battles."
		return
	if _busy:
		return
	_busy = true
	_info.text = "Creating the battle room..."
	var body := {"setup": setup, "rules": net.rules, "build": net.build, "name": "Custom battle"}
	var inv := str(net.accounts.data.get("invite", ""))
	if inv != "":
		body["invite"] = inv
	var r: Dictionary = await net.api.call_api("POST", "/api/custom", body, "", {"timeout": 20})
	_busy = false
	if not r["ok"]:
		_info.text = "Could not create the room: " + (str(r["message"]) if str(r["message"]) != "" else str(r["error"]))
		if str(r["error"]) == "invite_required":
			_info.text = "This server needs an invite key: create an online campaign once with it (it is remembered)."
		return
	_open_session(str(r["data"]["code"]), str(r["data"]["token"]), 0)
	_tele("custom_room", {"role": "host", "setup": CS.summary(setup)})


func _join() -> void:
	var net := _net()
	var code: String = NetScript.norm_code(_code_edit.text)
	if code.length() != 6:
		_info.text = "A code has 6 characters."
		return
	if net == null or not net.has_server() or (not net.available and not await net.check_server()):
		_info.text = "Online play needs the game server."
		return
	_info.text = "Joining..."
	var r: Dictionary = await net.api.call_api("POST", "/api/custom/join", {"code": code}, "", {})
	if not r["ok"]:
		_info.text = {"bad_code": "No open custom battle has that code.", "seat_taken": "Someone has joined that battle already.",
			"started": "That battle has started without you."}.get(str(r["error"]), "Could not join: " + str(r["message"]))
		return
	var d: Dictionary = r["data"]
	if str(d.get("rules", "")) != "" and str(d["rules"]) != net.rules:
		_info.text = "Your friend has a different version of the game: reload the page on both devices."
		return
	setup = d["setup"]
	_open_session(str(d["code"]), str(d["token"]), 1)
	_tele("custom_room", {"role": "join", "setup": CS.summary(setup)})


func _open_session(code: String, token: String, me: int) -> void:
	var net := _net()
	session = CoopSession.new()
	session.names = {0: "Player 1", 1: "Player 2"}
	session.colors = {0: PLAYER_COLORS[0], 1: PLAYER_COLORS[1]}
	add_child(session)
	session.setup_custom(net.api.base_url, code, token, me, func(st: Dictionary) -> Dictionary: return CS.build(st))
	session.setup_changed.connect(func():
		setup = session.setup_data.duplicate(true)
		_rebuild())
	session.changed.connect(_on_session)
	session.note.connect(func(t: String, _k: String): if _info != null: _info.text = t)
	session.failed.connect(func(_c: String, t: String): if _info != null: _info.text = "The room is gone: " + t)
	_rebuild()


func _on_session() -> void:
	if session == null:
		return
	if session.ls != null and not _started:
		# The battle started: hand the session to the battle view.
		_started = true
		_hand_over.call_deferred()
		return
	_refresh_lobby()


func _hand_over() -> void:
	var s = session
	remove_child(s)
	session = null
	_started = false
	_tele("custom_start", {"me": s.me, "setup": CS.summary(setup)})
	play_online.emit(s, setup.duplicate(true))
	_rebuild()


func _tele(kind: String, d: Dictionary) -> void:
	var t := get_node_or_null("/root/Telemetry")
	if t != null:
		t.event(kind, d)


var _lobby_label: Label
var _ready_btn: Button
var _start_btn: Button


func _lobby_view() -> Control:
	var p := Kit.panel(Color(0.1, 0.09, 0.05, 0.95), 8)
	var v := Kit.vbox(6)
	p.add_child(v)
	var h := Kit.flow(8)
	h.add_child(Kit.label("Code", Kit.FONT, Kit.COL_DIM))
	var cl := Kit.label(NetScript.show_code(session.custom_code), 30, Kit.COL_GOLD)
	cl.name = "custom_room_code"
	h.add_child(cl)
	h.add_child(Kit.icon_button("Copy", "copy", func(): DisplayServer.clipboard_set(NetScript.show_code(session.custom_code)), 70))
	_ready_btn = Kit.icon_button("Ready", "accept", func(): session.lobby_ready(not session.want_ready), 110, 16)
	_ready_btn.name = "custom_ready"
	h.add_child(_ready_btn)
	_start_btn = Kit.icon_button("Start battle", "battles", func(): session.start_battle(), 130, 16)
	_start_btn.name = "custom_start"
	_start_btn.visible = session.me == 0
	h.add_child(_start_btn)
	v.add_child(h)
	_lobby_label = Kit.label("", Kit.FONT_SMALL, Color.WHITE, true)
	v.add_child(_lobby_label)
	_refresh_lobby.call_deferred()
	return p


func _refresh_lobby() -> void:
	if session == null or _lobby_label == null or not is_instance_valid(_lobby_label):
		return
	var parts: Array[String] = []
	var all_ready := true
	for p in [0, 1]:
		var info: Dictionary = session.player(p)
		var side := CS.side_of_player(setup, p)
		var where: String = ["side 1, bottom", "side 2, top"][side] if side >= 0 else "no army"
		var st := "not here yet"
		if bool(info.get("on", false)):
			st = "ready" if bool(info.get("ready", false)) else "choosing"
			if not bool(info.get("ready", false)):
				all_ready = false
		parts.append("%s%s (%s): %s" % [session.player_name(p), " (you)" if p == session.me else "", where, st])
	var h2h := CS.side_of_player(setup, 0) != CS.side_of_player(setup, 1)
	var text := "   ".join(parts) + "\n" + ("Head-to-head: you fight each other." if h2h else "Co-op: you fight side by side.")
	text += " Player 1 sets up the battle; Player 2 may change the units of Player 2's armies."
	if session.build_error != "":
		text += "\n" + session.build_error
	_lobby_label.text = text
	_ready_btn.text = "Not ready" if session.want_ready else "Ready"
	_start_btn.disabled = not (all_ready and session.want_ready) or session.phase != "lobby"
