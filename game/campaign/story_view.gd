extends RefCounted
## The story campaign's view (campaign/cstory.gd; DESIGN "Story campaign: The
## Brethren's Due"): the dialogue panel (a coloured initial badge per
## character until there are portraits, the speaker, the lines, the choices),
## the pressures strip under the top bar (five gauges, and the free port's
## once Act 3 reveals it; a tap opens the story log), the story log (also
## from the Realm panel), the ending screen (the epilogue, the fates, the
## stats, "Continue in the sandbox") and captions over the story's fleets
## and places on the map. View only: it reads the state and answers choices
## through CStory.answer (a pure function, like a battle's result). What the
## player has already read is kept in the save's session ("story_seen", the
## last log entry shown; "story_end_seen", the ending screen), not in the
## state.

const CData := preload("res://campaign/cdata.gd")
const CState := preload("res://campaign/cstate.gd")
const CStory := preload("res://campaign/cstory.gd")
const CStorm := preload("res://campaign/cstorm.gd")
const CSea := preload("res://campaign/csea.gd")
const Kit := preload("res://game/campaign/ui_kit.gd")
const CGrid := preload("res://campaign/cgrid.gd")
const CCaptainV := preload("res://campaign/ccaptain.gd")
const StoryPortrait := preload("res://game/story_portrait.gd")

const GAUGES: Array[String] = ["purse", "attention", "favour", "storm", "haven", "port"]
const GAUGE_NAMES := {"purse": "Purse", "attention": "Armada", "favour": "Patron", "storm": "Storms", "haven": "Haven", "port": "Free port"}
const COL_OK := Color(0.45, 0.8, 0.45)
const COL_WARN := Color(0.95, 0.75, 0.3)
const COL_HOT := Color(0.95, 0.4, 0.3)
const COL_NARRATOR := Color(0.88, 0.82, 0.66)

var s  # the campaign screen
var strip: PanelContainer
var decide: Button
var _bars := {}    # gauge -> ProgressBar
var _vals := {}    # gauge -> Label
var _boxes := {}   # gauge -> its VBox (the free port's shows once revealed)
var marks: Node2D


func _init(screen) -> void:
	s = screen


func on() -> bool:
	return not (s.st as Dictionary).is_empty() and CStory.on(s.st)


## Build the strip (into the screen's interface) and the map captions (on
## the overlay's layer). Hidden outside a story campaign.
func setup() -> void:
	strip = Kit.panel(Color(0.08, 0.09, 0.08, 0.88), 5)
	strip.name = "story_strip"
	strip.position = Vector2(6, 52)  # under the top bar (campaign_screen TOP_H 46)
	strip.mouse_filter = Control.MOUSE_FILTER_STOP
	strip.visible = false
	strip.gui_input.connect(func(e):
		if e is InputEventMouseButton and not e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			show_log())
	var h := Kit.hbox(6)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip.add_child(h)
	for g in GAUGES:
		var v := Kit.vbox(1)
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var l := Kit.label(str(GAUGE_NAMES[g]), 11, Kit.COL_DIM)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(l)
		var bar := ProgressBar.new()
		bar.name = "gauge_" + g
		bar.show_percentage = false
		bar.max_value = 100
		bar.custom_minimum_size = Vector2(56, 7)
		bar.mouse_filter = Control.MOUSE_FILTER_PASS
		bar.add_theme_stylebox_override("background", Kit.box(Color(0.22, 0.22, 0.2), 0, 3))
		v.add_child(bar)
		h.add_child(v)
		_bars[g] = bar
		_vals[g] = l
		_boxes[g] = v
	decide = Kit.button("Decide", func(): s._next_step(), 0, 13)
	decide.name = "story_decide"
	decide.custom_minimum_size = Vector2(64, 30)
	decide.modulate = Color(1, 0.75, 0.5)
	decide.visible = false
	h.add_child(decide)
	s.ui.add_child(strip)
	s.ui.move_child(strip, 1)  # under the dialogs and the cover
	marks = Marks.new()
	marks.view = self
	s.overlay.add_child(marks)


## The strip's gauges and the map captions follow the state.
func refresh() -> void:
	if strip == null:
		return
	strip.visible = on() and str(s.st.get("phase", "")) != "over" and CStory.ending(s.st) == ""
	if marks != null:
		marks.visible = on() and CStory.ending(s.st) == ""
		marks.queue_redraw()
	if not strip.visible:
		return
	var st: Dictionary = s.st
	(_boxes["port"] as Control).visible = not CStory.fp(st).is_empty()
	for g in GAUGES:
		var gv := gauge(st, g)
		var bar: ProgressBar = _bars[g]
		bar.value = int(gv[0])
		bar.add_theme_stylebox_override("fill", Kit.box(gv[1], 0, 3))
		bar.tooltip_text = str(gv[2])
		(_vals[g] as Label).tooltip_text = str(gv[2])
	strip.tooltip_text = "Tap for the story so far"
	decide.visible = CStory.blocked(st) and not s.dialog_open()
	decide.text = "Decide" if not _next_choice(st).is_empty() else "Waiting"


## [value 0-100, colour, explanation] of gauge g.
static func gauge(st: Dictionary, g: String) -> Array:
	match g:
		"purse":
			var v := CStory.p(st, "purse")
			return [v, COL_OK if v < 40 else (COL_WARN if v < 65 else COL_HOT),
				"The crew's purse: %d. It rises every turn without plunder and falls with prizes, sacks and treasure. Grumbling at 40, desertion at 65, a vote on the captain at 85. Shares owed: %d gold." % [
				v, CStory.p(st, "owed")]]
		"attention":
			var a := CStory.attention(st)
			var inf := CSea.infamy(st, CStory.player(st))
			return [a, COL_OK if a < 30 else (COL_WARN if a < 35 else COL_HOT),
				"The Armada's attention: %d (your infamy %d, Spain's grudge %d). At 35 the Armada de Barlovento sails to hunt you, farther the higher it climbs." % [
				a, inf, CStory.p(st, "heat")]]
		"favour":
			var fv := CStory.p(st, "favour")
			if CStory.flag(st, "treaty"):
				return [fv, COL_HOT if fv < 20 else (COL_WARN if fv < 45 else COL_OK),
					"Patron favour: %d. Since the Treaty of Madrid, Sir Thomas Ashby has put a price on your head and Port Royal is shut to you." % fv]
			return [fv, COL_HOT if fv < 20 else (COL_WARN if fv < 45 else COL_OK),
				"Patron favour: %d. What the Governor of Jamaica, Sir Thomas Ashby, thinks of you: his letter of marque needs 30 (or gold), and his ports depend on it." % fv]
		"storm":
			var t := int(st["turn"])
			var n := CStorm.storms(st).size()
			if n > 0:
				return [100, COL_HOT, "Hurricane season: %d storm%s at sea. Their orange cones show where they go next turn; a friendly harbour takes a fifth of the harm." % [
					n, "" if n == 1 else "s"]]
			if CStorm.season(t):
				return [60, COL_WARN, "Hurricane season (summer): storms form east of the islands and move west."]
			return [20, COL_OK, "Out of season: the next hurricane season is next turn (summer)."]
		"haven":
			var hv := CStory.p(st, "haven")
			return [hv, COL_HOT if hv < 30 else (COL_WARN if hv < 55 else COL_OK),
				"Haven safety: %d. Tortuga's walls and a garrison of yours raise it; Spain's attention wears it down. Below 30 the haven is in danger." % hv]
		"port":
			if CStory.fp(st).is_empty():
				return [0, COL_HOT, ""]
			var parts := CStory.fp_parts(st)
			var sum := 0
			var lines: Array = []
			for pt in parts:
				sum += mini(int(pt[2]) * 100 / maxi(int(pt[3]), 1), 100)
				lines.append(("[done] " if int(pt[1]) == 1 else "[ ] ") + str(pt[4]))
			var n := CStory.fp_count(st)
			return [sum / maxi(parts.size(), 1), COL_OK if n >= 3 else (COL_WARN if n >= 1 else COL_HOT),
				"The free port, %d of 3: %s. Mendoza will come for it before the end; each part done makes that fight easier." % [n, "; ".join(lines)]]
	return [0, COL_OK, ""]


# ---------------------------------------------------------------- the flow ---

func _online() -> bool:
	return s.online != null


## The session the read markers live in: the seat's online session, or the save's.
func _ses() -> Dictionary:
	return s.online.session if _online() else (s.data.get("session", {}) as Dictionary)


func _ses_set(key: String, v: int) -> void:
	if _online():
		s.online.set_session_value(key, v)
	else:
		(s.data["session"] as Dictionary)[key] = v


func _seen() -> int:
	return int(_ses().get("story_seen", 0))


func _set_seen(n: int) -> void:
	_ses_set("story_seen", maxi(_seen(), n))


## The log entry e is something to read: news, or a crew vote's result.
static func _is_news(e: Dictionary) -> bool:
	return int(e["c"]) < 0 or e.has("v")


## The choice to answer now and the captain who answers it: [pending entry,
## faction] ([] none). Online it is the first one waiting for this seat; in
## hot seat the first one, and the next captain who has not voted on it.
func _next_choice(st: Dictionary) -> Array:
	if _online():
		var mine := CStory.pending_for(st, int(s.online.f))
		return [mine[0], int(s.online.f)] if not mine.is_empty() else []
	var all := CStory.pending_for(st)
	if all.is_empty():
		return []
	var pe: Dictionary = all[0]
	if CStory.is_vote(pe):
		var w := CStory.vote_waiting(st, pe)
		return [pe, int(w[0])] if not w.is_empty() else []
	return [pe, int(pe["f"])]


## A name for captain f: his captain's name, else the faction's.
static func captain_name(st: Dictionary, f: int) -> String:
	var best := {}
	for c in CCaptainV.of_faction(st, f):
		if best.is_empty() or int(c["fame"]) > int(best["fame"]):
			best = c
	return str(best["nm"]) if not best.is_empty() else CData.faction_name(f)


## The portrait key of captain f (the script's "captain" for the lead, "partner" for the second).
static func captain_key(st: Dictionary, f: int) -> String:
	return "captain" if CStory.captains(st).find(f) <= 0 else "partner"


## The next thing the story has to say: unread news first, then a choice
## waiting, then the ending screen (once). Shows it and returns true (the
## screen's flow carries on through _next_step when it is done); false when
## there is nothing. `news_only`: no choices (before pending battles: the
## news that opened one is read first, and the ending before the sandbox's
## battles).
func step(news_only: bool = false) -> bool:
	if not on():
		return false
	var st: Dictionary = s.st
	var news := {}
	for e in CStory.S(st)["log"]:
		if int(e["n"]) > _seen() and _is_news(e):
			news = e
			break
	var nc: Array = _next_choice(st) if not news_only else []
	var wait := {}  # (online) a vote that waits for the other captain
	if not news_only and nc.is_empty() and _online():
		var all := CStory.pending_for(st)
		if not all.is_empty():
			wait = all[0]
	var end_due := CStory.ending(st) != "" and not int(_ses().get("story_end_seen", 0)) != 0
	if news.is_empty() and nc.is_empty() and wait.is_empty() and not end_due:
		return false
	# Plan as the captain (like a pending battle does), the map on the scene.
	var pf := CStory.player(st) if nc.is_empty() else int(nc[1])
	if not _online() and s.f != pf and str(st["phase"]) != "over" and CState.alive(st, pf):
		if news.is_empty() and not nc.is_empty() and (st["humans"] as Array).size() > 1:
			_handover(nc[0], pf)  # (hot seat, two captains: the device goes to the one who votes)
			return true
		s._set_planner(pf, false)
	if news.is_empty() and nc.is_empty() and wait.is_empty():
		show_ending()
		return true
	if "--story-log" in OS.get_cmdline_user_args() and not _log_shown:
		_log_shown = true  # testing aid: the story log first
		show_log()
		return true
	if not news.is_empty():
		_focus(CStory.event_def(st, str(news["e"])))
		_show_news(news)
	elif not nc.is_empty():
		_focus(CStory.event_def(st, str(nc[0]["e"])))
		_show_choice(nc[0], 1 if "--story-choices" in OS.get_cmdline_user_args() else 0, int(nc[1]))  # (testing aid: the choices page)
	else:
		_focus(CStory.event_def(st, str(wait["e"])))
		_show_wait(wait)
	return true


## (Hot seat, two captains) Pass the device to captain f, who votes on pe.
func _handover(pe: Dictionary, f: int) -> void:
	var st: Dictionary = s.st
	s.cover.visible = true
	s.close_side()
	if "--story-nohand" in OS.get_cmdline_user_args():
		s.cover.visible = false  # (testing aid: straight to the vote)
		s._set_planner(f, false)
		_show_choice(pe, 0, f)
		return
	var box := Kit.vbox(12)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	var sw := Kit.hbox(10)
	sw.alignment = BoxContainer.ALIGNMENT_CENTER
	sw.add_child(portrait(captain_key(st, f), 56))
	sw.add_child(Kit.label("%s votes" % captain_name(st, f), 26))
	box.add_child(sw)
	box.add_child(Kit.label("Pass the device to the %s player: the crew has a choice to make. %s." % [
		CData.FACTIONS[f]["adj"], CData.date_text(int(st["turn"]))], 16, Kit.COL_DIM))
	s.show_dialog("", box, [["Cast my vote", func():
		s.cover.visible = false
		s._set_planner(f, false)
		_focus(CStory.event_def(st, str(pe["e"])))
		_show_choice(pe, 0, f)]])


## Centre the map on what event ev is about ("focus": a region key, an actor
## key, "flagship"; default: the flagship, once a turn).
var _focus_turn := -1
var _log_shown := false


func _focus(ev: Dictionary) -> void:
	var st: Dictionary = s.st
	var fk := str(ev.get("focus", ""))
	if fk == "" and _focus_turn == int(st["turn"]):
		return
	_focus_turn = int(st["turn"])
	var c := -1
	if fk != "" and fk != "flagship":
		var afl := CStory.actor_fleet(st, fk)
		if not afl.is_empty():
			c = CGrid.at(int(afl["x"]), int(afl["y"]))
		elif fk == "lair":
			c = CStory._sea_near(CStory._pos_cell(st, "lair"))
		elif CData.region_index(fk) >= 0:
			c = CGrid.site(CData.region_index(fk))
	if c < 0:
		var fl := CStory.flagship(st, CStory.player(st))
		if fl.is_empty():
			return
		c = CGrid.at(int(fl["x"]), int(fl["y"]))
	var px := float(CGrid.cell_px())
	var p := Vector2((CGrid.cx(c) + 0.5) * px, (CGrid.cy(c) + 0.5) * px)
	var vp: Vector2 = s._vp()
	s.zoom = 0.7 if vp.x < 1200 else 0.9
	s.offset = Vector2(vp.x * 0.5, 46.0 + (vp.y - 46.0) * 0.14) - p * s.zoom  # above the dialog
	s._clamp_view()
	s._refresh_map()


## End turn while a choice waits: show it instead.
func guard_end() -> bool:
	if on() and CStory.blocked(s.st):
		step()
		return true
	return false


func _show_news(e: Dictionary) -> void:
	_x = int(e.get("x", -1))
	var st: Dictionary = s.st
	var ev := CStory.event_def(st, str(e["e"]))
	var box := _event_box(st, ev, int(e["t"]))
	var n := int(e["n"])
	if e.has("v"):
		_show_vote_result(e)
		return
	s.show_dialog(_fill(str(ev.get("title", ""))), box, [["Continue", func():
		_set_seen(n)
		s.save()
		s._next_step()]], 640)
	refresh()


## A choice: the scene, then the choices with what each does. On a short
## screen (a phone) the scene is a page of its own and the choices the next.
func _show_choice(pe: Dictionary, page: int = 0, who: int = -1) -> void:
	_x = int(pe.get("x", -1))
	var st: Dictionary = s.st
	if who < 0:
		who = CStory.player(st)
	_asking = who
	var ev := CStory.event_def(st, str(pe["e"]))
	var compact: bool = (s._vp() as Vector2).y < 700.0
	var vote := CStory.is_vote(pe)
	var look := ["Look at the map", func():
		s.close_dialog()
		refresh()]
	if compact and page == 0:
		s.show_dialog(_fill(str(ev.get("title", ""))), _event_box(st, ev, int(pe["t"])), [look, ["Your vote" if vote else "Your call", func(): _show_choice(pe, 1, who)]], 660, true)
		refresh()
		return
	var box := Kit.vbox(10) if compact else _event_box(st, ev, int(pe["t"]))
	if compact:
		var lines: Array = ev.get("lines", [])
		if not lines.is_empty():
			box.add_child(_line(str(lines[-1][0]), str(lines[-1][1])))
	var f := who
	var ch: Array = ev.get("choices", [])
	if vote:
		var hd := Kit.hbox(8)
		hd.add_child(portrait(captain_key(st, f), 36))
		hd.add_child(Kit.label("Your vote, %s" % captain_name(st, f), Kit.FONT, Kit.COL_GOLD))
		box.add_child(hd)
		for v in pe["v"]:
			if int(v[0]) != f:
				box.add_child(Kit.label("%s has voted: %s" % [captain_name(st, int(v[0])), str(ch[int(v[1])]["t"])], Kit.FONT_SMALL, COL_WARN, true))
		if (pe["v"] as Array).is_empty():
			box.add_child(Kit.label("The crew votes with both captains. If you disagree, Mercy calls it by fame and crew.", Kit.FONT_SMALL, Kit.COL_DIM, true))
	else:
		box.add_child(Kit.section("Your call, Captain"))
	for k in ch.size():
		var c: Dictionary = ch[k]
		var why := CStory.answer_check(st, f, int(pe["id"]), k)
		var row := Kit.hbox(8)
		var say: Array = c.get("say", [])
		if say.size() >= 2 and StoryPortrait.has(str(say[0])):
			var pc := StoryPortrait.make_control(str(say[0]), 40)
			pc.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
			row.add_child(pc)
		var b := Kit.button(str(c["t"]), _choose.bind(int(pe["id"]), k), 0, 15)
		b.name = "story_choice_%d" % k
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.disabled = why != ""
		row.add_child(b)
		box.add_child(row)
		var hint := str(c.get("hint", ""))
		if why != "":
			hint = why + ". " + hint
		if hint != "":
			box.add_child(Kit.label(hint, Kit.FONT_SMALL, Kit.COL_BAD if why != "" else Kit.COL_DIM, true))
	var buttons: Array = [look]
	if compact:
		buttons.push_front(["Back", func(): _show_choice(pe, 0, who)])
	s.show_dialog(_fill(str(ev.get("title", ""))), box, buttons, 660, true)
	refresh()


## (Online, two captains) This seat has voted; the crew waits for the other.
func _show_wait(pe: Dictionary) -> void:
	_x = int(pe.get("x", -1))
	var st: Dictionary = s.st
	var ev := CStory.event_def(st, str(pe["e"]))
	var box := _event_box(st, ev, int(pe["t"]))
	var ch: Array = ev.get("choices", [])
	var me := int(s.online.f)
	box.add_child(Kit.section("The crew votes"))
	var mine := CStory.vote_of(pe, me)
	if mine >= 0:
		box.add_child(Kit.label("Your vote, %s: %s" % [captain_name(st, me), str(ch[mine]["t"])], Kit.FONT, COL_OK, true))
	var names: Array[String] = []
	for w in CStory.vote_waiting(st, pe):
		names.append(captain_name(st, int(w)))
	box.add_child(Kit.label("Waiting for %s." % " and ".join(names), Kit.FONT, COL_WARN, true))
	s.show_dialog(_fill(str(ev.get("title", ""))), box, [["Look at the map", func():
		s.close_dialog()
		refresh()]], 660, true)
	refresh()


var _asking := -1  # the captain whose choice is on screen
var _x := -1       # the nation the event on screen is about ("{nation}" / "{adj}" in its lines)


## Fill "{nation}" and "{adj}" of a line with the nation the event is about.
func _fill(text: String) -> String:
	if _x < 0 or _x >= CData.FACTIONS.size():
		return text
	return text.replace("{nation}", CData.faction_name(_x)).replace("{adj}", str(CData.FACTIONS[_x]["adj"]))


func _choose(pid: int, k: int) -> void:
	var st: Dictionary = s.st
	var f := _asking if _asking >= 0 else CStory.player(st)
	if CStory.answer_check(st, f, pid, k) != "":
		return
	if _online():
		_choose_online(pid, k)
		return
	var eid := ""
	for pe in CStory.pending_for(st):
		if int(pe["id"]) == pid:
			eid = str(pe["e"])
	var nst := CStory.answer(st, f, pid, k)
	_after_answer(nst, eid, f)


## The answer is in (hot seat: the new state; online: the adopted one).
func _after_answer(nst: Dictionary, eid: String, f: int) -> void:
	var settled := {}
	for e in CStory.S(nst)["log"]:
		if str(e["e"]) == eid and int(e["c"]) >= 0:
			settled = e
	# The choice is read now; what it set off is news still to show.
	if not settled.is_empty() and int(settled["n"]) > _seen():
		_set_seen(int(settled["n"]))
	s.st = nst
	if not _online():
		if s.f >= 0:
			s._replan()
		s.save()
	if settled.is_empty():
		s._next_step()  # (a vote still open: the other captain's turn)
		refresh()
		return
	if settled.has("v"):
		_show_vote_result(settled)
		return
	var ev := CStory.event_def(nst, eid)
	var c: Dictionary = ev["choices"][int(settled["c"])]
	var say: Array = c.get("say", [])
	if say.size() >= 2:
		var box := Kit.vbox(10)
		box.add_child(Kit.label("You: " + str(c["t"]), Kit.FONT_SMALL, Kit.COL_GOLD, true))
		box.add_child(_line(str(say[0]), str(say[1])))
		s.show_dialog(_fill(str(ev.get("title", ""))), box, [["Continue", func(): s._next_step()]], 600)
	else:
		s._next_step()
	refresh()


## (Online) Send the answer to the server and show what came of it.
func _choose_online(pid: int, k: int) -> void:
	var eid := ""
	for pe in CStory.pending_for(s.st):
		if int(pe["id"]) == pid:
			eid = str(pe["e"])
	var box := Kit.vbox(8)
	box.add_child(Kit.label("Sending your answer to the crew...", Kit.FONT, Color.WHITE, true))
	s.show_dialog("", box, [], 420)
	var r: Dictionary = await s.online.answer_story(pid, k)
	if not bool(r.get("ok", false)):
		s.close_dialog()
		if bool(r.get("network", false)):
			s.show_toast("Could not reach the server: your answer is not sent yet. Try again when the connection is back.")
		else:
			s.show_toast("The crew's choice moved on: %s" % str(r.get("message", r.get("error", ""))))
		s.st = s.online.st
		step()
		return
	_after_answer(s.online.st, eid, int(s.online.f))


## A crew vote settled: each captain's vote, then Mercy's word, then the winner's reply.
func _show_vote_result(e: Dictionary) -> void:
	_x = int(e.get("x", -1))
	var st: Dictionary = s.st
	var ev := CStory.event_def(st, str(e["e"]))
	var ch: Array = ev.get("choices", [])
	var box := Kit.vbox(10)
	box.name = "story_vote_result"
	box.add_child(Kit.section("The crew has voted"))
	for v in e["v"]:
		var row := Kit.hbox(10)
		row.add_child(portrait(captain_key(st, int(v[0])), 44))
		var col := Kit.vbox(2)
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_child(Kit.label(captain_name(st, int(v[0])), Kit.FONT, Kit.COL_GOLD))
		col.add_child(Kit.label(str(ch[int(v[1])]["t"]), Kit.FONT, Color.WHITE, true))
		row.add_child(col)
		box.add_child(row)
	var c: Dictionary = ch[int(e["c"])]
	var w := int(e.get("w", -1))
	if w >= 0:
		box.add_child(_line("mercy", "The captains are split, so I call it, as quartermaster. %s has the fame and the hands behind him: %s's way it is. The other crew will grumble. They always do." % [
			captain_name(st, w), captain_name(st, w)]))
	else:
		box.add_child(_line("mercy", "One mind, the pair of you. Good. The crew votes it, and it is done."))
	var say: Array = c.get("say", [])
	if say.size() >= 2:
		box.add_child(_line(str(say[0]), str(say[1])))
	var n := int(e["n"])
	s.show_dialog(_fill(str(ev.get("title", ""))), box, [["Continue", func():
		_set_seen(n)
		s.save()
		s._next_step()]], 640, true)
	refresh()


# ---------------------------------------------------------------- the ending ---

## The ending screen: the ending's title and paragraph, what became of each
## character, the captain's stats, then "Continue in the sandbox" (the
## campaign plays on without the story) or the story log.
func show_ending() -> void:
	var st: Dictionary = s.st
	var e := CStory.ending(st)
	var m := CStory.script_of(st).get_script_constant_map()
	var ed: Dictionary = (m.get("ENDINGS", {}) as Dictionary).get(e, {"title": e, "sub": "", "text": ""})
	var box := Kit.vbox(10)
	box.name = "story_ending"
	var tl := Kit.label(str(ed["title"]), 30, Kit.COL_GOLD)
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(tl)
	var sl := Kit.label(str(ed["sub"]), Kit.FONT, COL_NARRATOR, true)
	sl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(sl)
	box.add_child(Kit.label("%s. %s" % [str(m.get("TITLE", "")), CData.date_text(int(CStory.S(st).get("end_t", st["turn"])))],
		Kit.FONT_SMALL, Kit.COL_DIM, true))
	box.add_child(Kit.label(str(ed["text"]), Kit.FONT, COL_NARRATOR, true))
	box.add_child(Kit.section("What became of them"))
	for fd in CStory.fates(st):
		box.add_child(_line(str(fd[0]), str(fd[1])))
	box.add_child(Kit.section("The Captain's account"))
	var sx := CStory.end_stats(st)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 18)
	var rows := [["Plunder taken", "%d gold" % int(sx["plunder"])], ["Ships taken", str(int(sx["taken"]))],
		["Towns sacked", str(int(sx["sacked"]))], ["Fame", "%d (%s)" % [int(sx["fame"]), CCaptainV.tier_name(int(sx["fame"]))]],
		["Battles won / lost", "%d / %d" % [int(sx["won"]), int(sx["lost"])]], ["Infamy", str(int(sx["infamy"]))]]
	for rw in rows:
		grid.add_child(Kit.label(str(rw[0]), Kit.FONT, Kit.COL_DIM))
		grid.add_child(Kit.label(str(rw[1]), Kit.FONT, Color.WHITE))
	box.add_child(grid)
	var over := str(st["phase"]) == "over"
	var go := ["Continue" if over else "Continue in the sandbox", func():
		_ses_set("story_end_seen", 1)
		s.save()
		s._next_step()]
	s.show_dialog("", box, [["The story so far", func(): show_log()], go], 680, true)
	refresh()


# --------------------------------------------------------------- building ---

func _chars(st: Dictionary) -> Dictionary:
	var sc := CStory.script_of(st)
	return sc.get_script_constant_map().get("CHARS", {}) if sc != null else {}


func _event_box(st: Dictionary, ev: Dictionary, t: int) -> VBoxContainer:
	var box := Kit.vbox(10)
	var acts: Array = CStory.script_of(st).get_script_constant_map().get("ACTS", [])
	var act := int(ev.get("act", 0))
	if act < 0:
		act = int(CStory.S(st)["act"])
	var sub := "%s. %s" % [str(acts[act]) if act < acts.size() else "", CData.date_text(t)]
	if int(ev.get("tip", 0)) != 0:
		sub = "From Vane's logbook. " + CData.date_text(t)
	box.add_child(Kit.label(sub, Kit.FONT_SMALL, Kit.COL_DIM, true))
	for ln in ev.get("lines", []):
		box.add_child(_line(str(ln[0]), str(ln[1])))
	return box


## One line: a badge, the speaker's name and role, the words (the narrator:
## the words alone, in parchment colour).
func _line(who: String, text: String) -> Control:
	text = _fill(text)
	if who == "":
		return Kit.label(text, Kit.FONT, COL_NARRATOR, true)
	var ch: Dictionary = _chars(s.st).get(who, {"name": who, "role": "", "col": "666666"})
	var h := Kit.hbox(10)
	h.add_child(portrait(who, 48))
	var v := Kit.vbox(2)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var nm := Kit.hbox(6)
	nm.add_child(Kit.label(str(ch["name"]), Kit.FONT, Kit.COL_GOLD))
	if str(ch.get("role", "")) != "":
		nm.add_child(Kit.label(str(ch["role"]), Kit.FONT_SMALL, Kit.COL_DIM))
	v.add_child(nm)
	v.add_child(Kit.label(text, Kit.FONT, Color.WHITE, true))
	h.add_child(v)
	return h


## The portrait of character `who` (a CHARS key) at sz px: the code-drawn one
## (game/story_portrait.gd), else the faction's mark if the script names one
## ("mark"), else the badge.
func portrait(who: String, sz: float) -> Control:
	if StoryPortrait.has(who):
		var pc := StoryPortrait.make_control(who, sz)
		pc.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		return pc
	var ch: Dictionary = _chars(s.st).get(who, {"name": who, "role": "", "col": "666666"})
	var fi := CData.faction_index(str(ch.get("mark", ""))) if ch.has("mark") else -1
	if fi >= 0:
		var m := Kit.faction_mark(fi, sz)
		m.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		return m
	return badge(ch, sz)


## A portrait placeholder: the character's initial on a disc of their colour.
static func badge(ch: Dictionary, sz: float) -> Control:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", Kit.box(Color(str(ch.get("col", "666666"))), 0, int(sz / 2)))
	p.custom_minimum_size = Vector2(sz, sz)
	p.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var nm := str(ch.get("name", "?"))
	var parts := nm.replace("\"", "").split(" ", false)
	var ini := nm.substr(0, 1)
	if parts.size() >= 2 and not nm.begins_with("Don") and not nm.begins_with("Sir") and not nm.begins_with("The"):
		ini = parts[0].substr(0, 1) + parts[parts.size() - 1].substr(0, 1)
	elif parts.size() >= 2:
		ini = parts[parts.size() - 1].substr(0, 1)
	var l := Kit.label(ini, int(sz * 0.38), Color.WHITE)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	l.add_theme_constant_override("outline_size", 3)
	p.add_child(l)
	return p


## The Grudges block: the attention toward Spain with the Armada's mark, and each
## provoked nation with its emblem, why and the turns left.
func grudges_box(st: Dictionary) -> VBoxContainer:
	var box := Kit.vbox(4)
	box.name = "story_grudges"
	box.add_child(Kit.section("Grudges"))
	var att := CStory.attention(st)
	var hunt := int(CStory._c(st, "ARMADA_HUNT_ATT", 35))
	var bar := GrudgeBar.new()
	bar.value = att
	bar.mark = hunt
	bar.custom_minimum_size = Vector2(0, 34)
	bar.tooltip_text = "The captains' attention toward Spain: %d. At %d the Armada sails." % [att, hunt]
	box.add_child(bar)
	var gl := CStory.grudges(st)
	if gl.is_empty():
		box.add_child(Kit.label("No nation holds a grudge: the haven is shielded.", Kit.FONT_SMALL, COL_OK, true))
	for g in gl:
		var row := Kit.hbox(8)
		row.name = "grudge_row"
		row.add_child(Kit.faction_mark(int(g["f"]), 22))
		var why := ""
		match str(g["w"]):
			"sack":
				why = "you sacked %s" % _port_name(int(g["r"]))
			"blockade":
				why = "you blockaded %s" % _port_name(int(g["r"]))
			_:
				why = "the Armada's attention (%d)" % att
		var left := "" if int(g["left"]) < 0 else ", %d turn%s left" % [int(g["left"]), "" if int(g["left"]) == 1 else "s"]
		row.add_child(Kit.label("%s: %s%s" % [CData.faction_name(int(g["f"])), why, left], Kit.FONT_SMALL, COL_WARN, true))
		box.add_child(row)
	return box


static func _port_name(r: int) -> String:
	return str(CData.REGIONS[r]["city"]) if r >= 0 else "a port"


## The attention bar with its mark ("the Armada sails" at the hunt threshold).
class GrudgeBar extends Control:
	var value := 0
	var mark := 35

	func _draw() -> void:
		var w := size.x
		var y := size.y - 14.0
		draw_rect(Rect2(0, y, w, 8), Color(0.22, 0.22, 0.2))
		var col := Color(0.45, 0.8, 0.45) if value < mark - 10 else (Color(0.95, 0.75, 0.3) if value < mark else Color(0.95, 0.4, 0.3))
		draw_rect(Rect2(0, y, w * clampf(value / 100.0, 0.0, 1.0), 8), col)
		var mx := w * clampf(mark / 100.0, 0.0, 1.0)
		draw_line(Vector2(mx, y - 6), Vector2(mx, y + 12), Color(1, 1, 1), 2.0)
		var font := ThemeDB.fallback_font
		draw_string(font, Vector2(0, 11), "Attention toward Spain: %d" % value, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.85, 0.85, 0.8))
		draw_string(font, Vector2(mx + 4, 11), "%d: the Armada sails" % mark, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 0.85, 0.5))


## The story so far (the strip's tap, the Realm panel's "Story log"): the
## pressures explained, then every entry, newest first.
func show_log() -> void:
	if not on():
		return
	var st: Dictionary = s.st
	var box := Kit.vbox(8)
	var acts: Array = CStory.script_of(st).get_script_constant_map().get("ACTS", [])
	var act := int(CStory.S(st)["act"])
	box.add_child(Kit.label("%s. %s." % [str(CStory.script_of(st).get_script_constant_map().get("TITLE", "")),
		str(acts[mini(act, acts.size() - 1)])], Kit.FONT, Kit.COL_GOLD, true))
	for g in GAUGES:
		var gv := gauge(st, g)
		if str(gv[2]) == "":
			continue  # (the free port before Act 3 reveals it)
		var row := Kit.hbox(8)
		row.add_child(Kit.swatch(gv[1], 12))
		row.add_child(Kit.label(str(gv[2]), Kit.FONT_SMALL, Color.WHITE, true))
		box.add_child(row)
	box.add_child(grudges_box(st))
	var lg: Array = CStory.S(st)["log"]
	var last_t := -1
	for i in range(lg.size() - 1, -1, -1):
		var e: Dictionary = lg[i]
		var ev := CStory.event_def(st, str(e["e"]))
		_x = int(e.get("x", -1))
		if int(e["t"]) != last_t:
			last_t = int(e["t"])
			box.add_child(Kit.section(CData.date_text(last_t)))
		box.add_child(Kit.label(str(ev.get("title", e["e"])), Kit.FONT, Kit.COL_GOLD, true))
		for ln in ev.get("lines", []):
			var who := str(ln[0])
			var nm := str(_chars(st).get(who, {}).get("name", ""))
			box.add_child(Kit.label((nm + ": " if nm != "" else "") + _fill(str(ln[1])), Kit.FONT_SMALL,
				Color.WHITE if nm != "" else COL_NARRATOR, true))
		if int(e["c"]) >= 0:
			var ch: Dictionary = ev["choices"][int(e["c"])]
			box.add_child(Kit.label("You chose: " + str(ch["t"]), Kit.FONT_SMALL, Kit.COL_GOOD, true))
			var say: Array = ch.get("say", [])
			if say.size() >= 2:
				var nm2 := str(_chars(st).get(str(say[0]), {}).get("name", ""))
				box.add_child(Kit.label((nm2 + ": " if nm2 != "" else "") + str(say[1]), Kit.FONT_SMALL, Color.WHITE, true))
	var buttons: Array = [["Close", Callable()]]
	if CStory.blocked(st):
		buttons.push_front(["Decide", func(): s._next_step()])
	if CStory.ending(st) != "":
		buttons.push_front(["The ending", func(): show_ending()])
	s.show_dialog("The story so far", box, buttons, 700, true)


## Testing aid (main.gd --story=seed[:turns]): save data for a new story
## campaign after `turns` turns played by game/campaign/story_autoplay.gd
## (--story-path=first | random | republic | pardon | legend; the choices of
## the last turn are left waiting); with turns, everything up to then is
## marked read (--story-show=ID: from the last entry of event ID on is
## unread; "ending": the ending screen is due).
static func autoplay(sd: int, turns: int) -> Dictionary:
	(load("res://game/campaign/pack_view.gd") as GDScript).call("use_pack", "west")
	var path := "first"
	var show := ""
	var coop := "--story-coop" in OS.get_cmdline_user_args()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--story-path="):
			path = a.get_slice("=", 1)
		elif a.begins_with("--story-show="):
			show = a.get_slice("=", 1)
	var SA: GDScript = load("res://game/campaign/story_autoplay.gd")
	var st: Dictionary = SA.call("play", sd, turns, path, sd, false, false, coop, 0)
	var pf := CStory.player(st)
	if coop and "--story-vote-first" in OS.get_cmdline_user_args():
		var pe0 := CStory.pending_for(st, pf)  # (testing aid: the lead has voted for the first choice)
		if not pe0.is_empty():
			st = CStory.answer(st, pf, int(pe0[0]["id"]), 0)
	if "--story-grudge" in OS.get_cmdline_user_args():
		# (testing aid: Spain's port sacked and the attention up, Mercy's lines due)
		CStory.S(st)["p"]["heat"] = 25
		CStory._provoke(st, CData.faction_index("tierra_firme"), int(st["turn"]), "sack", CData.region_index("cartagena"))
		CStory.check(st)
	var ses := {"subs": [], "plans": {}, "seen": {}}
	if turns > 0:
		ses["seen"] = {str(pf): int(st["turn"])}
		var last := 0
		for e in CStory.S(st)["log"]:
			last = int(e["n"])
			if show != "" and str(e["e"]) == show:
				ses["story_seen"] = int(e["n"]) - 1
		if not ses.has("story_seen"):
			ses["story_seen"] = last
	return {"state": st, "session": ses}


## Captions over the story's fleets and places (on the overlay's layer,
## drawn after it). Redrawn when the view moves or the state changes.
class Marks extends Node2D:
	const CStoryM := preload("res://campaign/cstory.gd")
	const CFleetM := preload("res://campaign/cfleet.gd")
	const CDataM := preload("res://campaign/cdata.gd")
	const CGridM := preload("res://campaign/cgrid.gd")
	const MapOverlayM := preload("res://game/campaign/map_overlay.gd")
	var view
	var _xf := Transform2D.IDENTITY

	func _process(_d: float) -> void:
		if view != null and view.decide != null and view.on():
			var want: bool = CStoryM.blocked(view.s.st) and not view.s.dialog_open() and str(view.s.st.get("phase", "")) == "plan"
			if view.decide.visible != want:
				view.decide.visible = want
		var ov = get_parent()
		if ov != null and ov.xform != _xf:
			_xf = ov.xform
			queue_redraw()

	func _draw() -> void:
		if view == null or not view.on():
			return
		var ov = get_parent()
		var st: Dictionary = view.s.st
		var sc := CStoryM.script_of(st)
		var mk: Dictionary = sc.get_script_constant_map().get("MARKS", {}) if sc != null else {}
		var font := ThemeDB.fallback_font
		for a in CStoryM.S(st)["actors"]:
			var fl := CStoryM.actor_fleet(st, str(a["k"]))
			if fl.is_empty():
				continue
			var p: Vector2 = ov.to_screen(MapOverlayM.cell_point(CFleetM.cell(fl)))
			var prize: bool = (sc.get_script_constant_map().get("PRIZES", []) as Array).has(str(a["k"]))
			var col := Color(0.95, 0.35, 0.3) if not prize else Color(1.0, 0.82, 0.35)
			_pin(font, p + Vector2(0, -26), str(mk.get(str(a["k"]), a["k"])), col)
		# The flota, once the story has pointed at it.
		if CStoryM.flag(st, "flota_seen"):
			for fl in CStoryM._flotas(st):
				var fp: Vector2 = ov.to_screen(MapOverlayM.cell_point(CFleetM.cell(fl)))
				_pin(font, fp + Vector2(0, -26), str(mk.get("flota", "The flota")), Color(1.0, 0.82, 0.35))
		# Places the story points at (the great raid's target).
		for tg in (sc.get_script_constant_map().get("TARGETS", []) if sc != null else []):
			if not CStoryM.flag(st, str(tg[0])) or CStoryM.flag(st, str(tg[1])):
				continue
			var tgr := CDataM.region_index(str(tg[2]))
			if tgr < 0:
				continue
			var tp: Vector2 = ov.to_screen(MapOverlayM.cell_point(CGridM.site(tgr)))
			var rr := maxf(float(CGridM.cell_px()) * 2.5 * float(ov.zoom), 16.0)
			for i in 16:
				var a1 := TAU * i / 16.0
				draw_arc(tp, rr, a1, a1 + TAU / 32.0, 4, Color(1.0, 0.82, 0.35), 2.0, true)
			_pin(font, tp + Vector2(0, rr + 14), str(tg[3]), Color(1.0, 0.82, 0.35))
		var hr := CDataM.region_index(str(sc.get_script_constant_map().get("HAVEN", ""))) if sc != null else -1
		if hr >= 0 and CStoryM.captains(st).has(int(st["regions"][hr]["owner"])):
			var hp: Vector2 = ov.to_screen(MapOverlayM.cell_point(CGridM.site(hr)))
			var hv := CStoryM.p(st, "haven")
			var hc := Color(0.5, 0.9, 0.5) if hv >= 55 else (Color(1.0, 0.8, 0.35) if hv >= 30 else Color(1.0, 0.45, 0.35))
			draw_arc(hp, 22.0, 0, TAU, 40, hc, 2.0, true)
			var hname := str(mk.get("free_port" if not CStoryM.fp(st).is_empty() else "haven", "Haven"))
			_pin(font, hp + Vector2(0, 34), "%s (%d)" % [hname, hv], hc)
		if CStoryM.flag(st, "hunt_boucher") and not CStoryM.flag(st, "won_boucher") and not CStoryM.flag(st, "lost_boucher"):
			var lc := CStoryM._sea_near(CStoryM._pos_cell(st, "lair"))
			if lc >= 0:
				var lp: Vector2 = ov.to_screen(MapOverlayM.cell_point(lc))
				var r := float(CGridM.cell_px()) * 3.0 * float(ov.zoom)
				for i in 16:
					var a0 := TAU * i / 16.0
					draw_arc(lp, maxf(r, 14.0), a0, a0 + TAU / 32.0, 4, Color(1, 0.4, 0.3), 2.0, true)
				_pin(font, lp + Vector2(0, maxf(r, 14.0) + 14), str(mk.get("lair", "Lair")), Color(1, 0.55, 0.45))

	func _pin(font: Font, p: Vector2, text: String, col: Color) -> void:
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		var at := p + Vector2(-w * 0.5, 0)
		draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, 4, Color(0, 0, 0, 0.85))
		draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, col)
