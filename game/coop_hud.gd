extends CanvasLayer
## The battle view's live co-op parts (milestone 5), over the normal HUD:
## - a strip at the top left: each human player of the battle (faction
##   colour and name, host mark, connected / disconnected / not joined,
##   this device's round trip);
## - a status line under the top bar: waiting for a player, catching up,
##   resyncing, connection lost;
## - the lobby panel before the start (who is in, Start / Leave, the
##   automatic start count);
## - the vote chips under Pause and the speed button (who asked; Accept /
##   No for the other player);
## - the Continue / Wait prompt when a disconnected player holds the battle
##   up for 10 s.
## It only reads the session (game/net/coop_session.gd) and calls its
## request methods; panels are registered with the HUD so touches on them
## never reach the battlefield.

const Kit := preload("res://game/campaign/ui_kit.gd")
const CData := preload("res://campaign/cdata.gd")

signal leave_pressed

var coop        ## CoopSession
var hud         ## Hud
var region_name := ""
var _root: Control
var _strip: HBoxContainer
var _status: Label
var _lobby: PanelContainer
var _lobby_box: VBoxContainer
var _prompt: PanelContainer
var _prompt_box: VBoxContainer
var _pause_chip: PanelContainer
var _speed_chip: PanelContainer
var _t := 0.0
var _sig := ""
var _flash := ""
var _flash_until := 0.0


func build(p_coop, p_hud) -> void:
	coop = p_coop
	hud = p_hud
	layer = 2
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_strip = Kit.hbox(4)
	_strip.position = Vector2(6, 6 + 42 + 6)
	_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_strip)
	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 17)
	_status.add_theme_color_override("font_outline_color", Color.BLACK)
	_status.add_theme_constant_override("outline_size", 6)
	_status.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_status.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.position.y = 6 + 42 + 40
	_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_status)
	_lobby = Kit.panel(Color(0.08, 0.1, 0.09, 0.93), 14)
	_lobby_box = Kit.vbox(8)
	_lobby.add_child(_lobby_box)
	_root.add_child(_lobby)
	_prompt = Kit.panel(Color(0.12, 0.08, 0.06, 0.95), 14)
	_prompt_box = Kit.vbox(8)
	_prompt.add_child(_prompt_box)
	_prompt.visible = false
	_root.add_child(_prompt)
	_pause_chip = Kit.panel(Color(0, 0, 0, 0.75), 4)
	_speed_chip = Kit.panel(Color(0, 0, 0, 0.75), 4)
	_pause_chip.visible = false
	_speed_chip.visible = false
	_root.add_child(_pause_chip)
	_root.add_child(_speed_chip)
	for c in [_lobby, _prompt, _pause_chip, _speed_chip]:
		hud.add_ui_control(c)
	coop.changed.connect(refresh)
	refresh()


func _process(delta: float) -> void:
	_t -= delta
	if _t <= 0.0:
		_t = 0.25
		refresh()


func fname(f: int) -> String:
	return coop.player_name(f) if f >= 0 else "nobody"


func _swatch(col: Color, s: float = 12.0) -> ColorRect:
	var r := ColorRect.new()
	r.color = col
	r.custom_minimum_size = Vector2(s, s)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


## Rebuild what changed (cheap; called on session changes and 4x a second).
func refresh() -> void:
	if coop == null:
		return
	var ls = coop.ls
	var sig := "%s|%d|%s|%s|%d|%d|%d|%d|%s|%s|%s" % [coop.phase, coop.host, str(coop.roster), str(coop.waiting),
		coop.takeover_offer, ls.vote_pause_by if ls else -2, ls.vote_speed_by if ls else -2,
		ls.paused if ls else -1, str(ls.active if ls else []), str(int(coop.start_in())), coop.room.state]
	_refresh_status()
	_place_chips()
	_center(_lobby)
	_center(_prompt)
	if sig == _sig:
		return
	_sig = sig
	_refresh_strip()
	_refresh_lobby()
	_refresh_prompt()
	_refresh_chips()
	_center.call_deferred(_lobby)
	_center.call_deferred(_prompt)


## Centre a panel in the space between the top bar and the unit cards.
func _center(p: PanelContainer) -> void:
	if not p.visible:
		return
	p.reset_size()
	var vp := _root.size
	var top := 60.0
	var bottom: float = hud.bottom_height() if hud != null else 0.0
	var y := top + maxf((vp.y - top - bottom - p.size.y) * 0.5, 0.0)
	if y + p.size.y > vp.y - 4.0:
		y = maxf(vp.y - p.size.y - 4.0, 4.0)
	p.position = Vector2(maxf((vp.x - p.size.x) * 0.5, 4.0), y)


func _player_state(f: int) -> String:
	var p: Dictionary = coop.player(f)
	var ls = coop.ls
	if f == coop.me:
		if coop.room.state != "open":
			return "connecting"
		return "%d ms" % int(coop.room.srtt_ms) if coop.room.srtt_ms >= 0.0 else "online"
	if p.is_empty():
		return "not here"
	if not bool(p.get("on", false)):
		return "disconnected"
	if ls != null and not ls.is_active(f):
		return "joining" if bool(p.get("joining", false)) or not bool(p.get("dropped", false)) else "left"
	return "online"


func _refresh_strip() -> void:
	for c in _strip.get_children():
		c.queue_free()
	for f in coop.humans:
		var fi := int(f)
		var chip := Kit.panel(Color(0, 0, 0, 0.55), 4)
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var h := Kit.hbox(4)
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(_swatch(coop.player_color(fi)))
		var st := _player_state(fi)
		var col := Color.WHITE
		if st == "disconnected" or st == "left":
			col = Kit.COL_BAD
		elif st == "not here" or st == "joining" or st == "connecting":
			col = Kit.COL_DIM
		var nm := fname(fi) + (" *" if fi == coop.host else "")
		var l := Kit.label("%s  %s" % [nm, st], 12, col)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(l)
		chip.add_child(h)
		_strip.add_child(chip)


## A short message in the status line.
func flash(text: String, sec: float = 2.5) -> void:
	_flash = text
	_flash_until = Time.get_ticks_msec() / 1000.0 + sec
	_refresh_status()


func _refresh_status() -> void:
	var t := ""
	var col := Color.WHITE
	var ls = coop.ls
	if _flash != "" and Time.get_ticks_msec() / 1000.0 < _flash_until:
		t = _flash
	elif coop.room.state == "retrying" or coop.room.state == "connecting" and coop.phase != "connecting":
		t = "Connection lost: reconnecting..."
		col = Kit.COL_BAD
	elif coop.phase == "sync" and ls != null:
		t = "Out of step: resyncing..."
		col = Kit.COL_GOLD
	elif coop.phase == "sync":
		t = "Loading the battle from %s..." % fname(coop.host)
	elif coop.catching_up and ls != null:
		var left: int = maxi(ls.max_mark(coop.me) - ls.frame, 0)
		t = "Catching up %d%%" % clampi(100 - left * 100 / maxi(coop.catchup_total, 1), 0, 99)
	elif not coop.waiting.is_empty() and coop.wait_sec >= 1.0:
		var names: Array[String] = []
		for p in coop.waiting:
			names.append(fname(int(p)))
		t = "Waiting for %s..." % " and ".join(names)
		col = Kit.COL_GOLD
	elif ls != null and coop.phase == "live" and not ls.is_active(coop.me):
		t = "Joining..." if coop.admitted_at < 0 else ""
	_status.text = t
	_status.add_theme_color_override("font_color", col)
	_status.visible = t != ""


func _refresh_lobby() -> void:
	for c in _lobby_box.get_children():
		c.queue_free()
	var lobby_on: bool = coop.phase in ["connecting", "lobby", "gone"] and coop.ls == null
	_lobby.visible = lobby_on
	if not lobby_on:
		return
	var title := "Live battle%s" % ((" at " + region_name) if region_name != "" else "")
	_lobby_box.add_child(Kit.label(title, Kit.FONT_TITLE, Kit.COL_GOLD))
	if coop.phase == "connecting":
		_lobby_box.add_child(Kit.label("Connecting...", Kit.FONT, Color.WHITE))
	elif coop.phase == "gone":
		_lobby_box.add_child(Kit.label("The room is closed.", Kit.FONT, Kit.COL_BAD))
	else:
		for f in coop.humans:
			var h := Kit.hbox(6)
			h.add_child(_swatch(coop.player_color(int(f)), 14))
			var on: bool = coop.connected(int(f))
			var who := fname(int(f)) + (" (you)" if int(f) == coop.me else "")
			h.add_child(Kit.label("%s: %s" % [who, "here" if on else "waiting for them to join"], Kit.FONT,
				Color.WHITE if on else Kit.COL_DIM))
			_lobby_box.add_child(h)
		var s: float = coop.start_in()
		if s >= 0.0:
			_lobby_box.add_child(Kit.label("Everyone is here: starting in %d..." % ceili(s), Kit.FONT, Kit.COL_GOOD))
		elif coop.is_host():
			_lobby_box.add_child(Kit.label("Your ally has been asked to join (Discord). Start now to fight alone; they can still join during the battle.",
				Kit.FONT_SMALL, Kit.COL_DIM, true))
		else:
			_lobby_box.add_child(Kit.label("Waiting for %s to start the battle." % fname(coop.host), Kit.FONT_SMALL, Kit.COL_DIM, true))
	var row := Kit.hbox(8)
	row.alignment = BoxContainer.ALIGNMENT_END
	if coop.phase == "lobby" and coop.is_host():
		var sb := Kit.button("Start now", func(): coop.start_battle(), 110)
		sb.name = "coop_start"
		row.add_child(sb)
	var lb := Kit.button("Leave", func(): leave_pressed.emit(), 90)
	lb.name = "coop_leave"
	row.add_child(lb)
	_lobby_box.add_child(row)
	_lobby.custom_minimum_size = Vector2(minf(420.0, _root.size.x - 20.0), 0)
	_lobby.reset_size()


func _refresh_prompt() -> void:
	for c in _prompt_box.get_children():
		c.queue_free()
	var p: int = coop.takeover_offer
	_prompt.visible = p >= 0
	if p < 0:
		return
	_prompt_box.add_child(Kit.label("%s has disconnected" % fname(p), Kit.FONT_TITLE, Kit.COL_GOLD))
	_prompt_box.add_child(Kit.label("The battle is waiting for them. Continue without them (you command their units until they are back), or wait a little longer.",
		Kit.FONT_SMALL, Color.WHITE, true))
	var row := Kit.hbox(8)
	row.alignment = BoxContainer.ALIGNMENT_END
	var cb := Kit.button("Continue without %s" % fname(p), func(): coop.continue_without(p), 0)
	cb.name = "coop_continue"
	row.add_child(cb)
	var wb := Kit.button("Wait", func(): coop.wait_longer(), 80)
	wb.name = "coop_wait"
	row.add_child(wb)
	_prompt_box.add_child(row)
	_prompt.custom_minimum_size = Vector2(minf(440.0, _root.size.x - 20.0), 0)
	_prompt.reset_size()


## Vote chips: the requester's colour and what they asked for; on the other
## player's screen Accept / No.
func _refresh_chips() -> void:
	var ls = coop.ls
	_fill_chip(_pause_chip, ls.vote_pause_by if ls else -1,
		("Pause?" if ls and ls.vote_pause_want == 1 else "Resume?"), 0)
	var q: int = ls.vote_speed_q if ls else 4
	var sp := "%sx?" % (("%.1f" % (q / 4.0)) if q < 4 else str(q / 4))
	_fill_chip(_speed_chip, ls.vote_speed_by if ls else -1, sp, 1)


func _fill_chip(chip: PanelContainer, by: int, what: String, kind: int) -> void:
	for c in chip.get_children():
		c.queue_free()
	chip.visible = by >= 0
	if by < 0:
		return
	var h := Kit.hbox(4)
	h.add_child(_swatch(coop.player_color(by), 12))
	if by == coop.me:
		h.add_child(Kit.label("%s asked" % what, 12, Color.WHITE))
	else:
		h.add_child(Kit.label("%s %s" % [fname(by), what], 12, Color.WHITE))
		var yes := Kit.button("Accept", func(): coop.answer(kind, true), 0, 12)
		yes.name = "vote_yes_%d" % kind
		yes.custom_minimum_size.y = 30
		h.add_child(yes)
		var no := Kit.button("No", func(): coop.answer(kind, false), 0, 12)
		no.name = "vote_no_%d" % kind
		no.custom_minimum_size.y = 30
		h.add_child(no)
	chip.add_child(h)
	chip.reset_size()


func _place_chips() -> void:
	for pair in [[_pause_chip, hud.pause_button], [_speed_chip, hud.speed_button]]:
		var chip: PanelContainer = pair[0]
		var b: Control = pair[1]
		if not chip.visible:
			continue
		var r: Rect2 = b.get_global_rect()
		chip.reset_size()
		var x := clampf(r.position.x + r.size.x - chip.size.x, 4.0, _root.size.x - chip.size.x - 4.0)
		var y := r.position.y + r.size.y + 4.0
		if pair[0] == _speed_chip and _pause_chip.visible:
			y += _pause_chip.size.y + 4.0
		chip.position = Vector2(x, y)
