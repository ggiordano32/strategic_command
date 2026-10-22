extends SceneTree
## The sea battle screen's help (game/sea_book.gd, game/sea_battle.gd), headless
## or with a window (screenshots with --out=DIR):
##   godot --headless --script res://tests/sea_help_test.gd
##   godot --resolution 1280x720 --script res://tests/sea_help_test.gd -- --out=/some/dir
## Every order button has a tooltip, a long press opens the help card, a tap
## closes it, a sail / shot change shows the hint, the status line gives the
## speed share, the Ship book opens (pausing solo) and lists every ship row.
## Douse (2026-10-22): no Douse button while she is sound; set alight, the bar
## shows it with its tip, a press douses her (the telemetry counter), and the
## Fire page explains fires, the magazine and Douse.

const SeaBattle := preload("res://game/sea_battle.gd")
const SeaSim := preload("res://sim/sea_sim.gd")
const ST := preload("res://sim/sea_types.gd")
const Checks := preload("res://tests/sea_checks.gd")

var sb: Node2D
var _ok := true
var _frame := 0
var _step := 0
var out := ""


func _check(c: bool, what: String) -> void:
	print(("PASS " if c else "FAIL ") + what)
	if not c:
		_ok = false


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	var scn := Checks.scenario("boarding")
	scn["ai_sides"] = [0, 1]
	(scn["units"] as Array).append({"side": 0, "t": "fire_ship"})
	sb = SeaBattle.new()
	sb.scenario = scn
	sb.seed_value = 3
	root.add_child(sb)


func _shot(name: String) -> void:
	if out != "":
		root.get_texture().get_image().save_png(out.path_join(name + ".png"))


func _btn(nm: String) -> Button:
	return sb.find_child(nm, true, false) as Button


func _process(_d: float) -> bool:
	_frame += 1
	if _frame < 6:
		return false
	match _step:
		0:
			var names := ["sea_full", "sea_battle_sail", "sea_stop", "sea_round", "sea_chain", "sea_grape", "sea_fire", "sea_board", "sea_hold", "sea_flee"]
			var all_tip := true
			for n in names:
				var b := _btn(n)
				if b == null or b.tooltip_text.strip_edges() == "" or b.tooltip_text.contains("!"):
					all_tip = false
					print("  no tooltip: ", n)
			_check(all_tip, "every order button has a tooltip")
			_check(_btn("sea_chain").tooltip_text.contains("%d m" % int(sb.sim.shot_range(sb.selection[0], ST.SHOT_CHAIN))),
				"the chain tooltip quotes the sim's range: " + _btn("sea_chain").tooltip_text)
			_check(sb._info.text.contains("(100 %)") or sb._info.text.contains("(75 %)") or sb._info.text.contains("(0 %)"),
				"the status line gives the speed share first: " + sb._info.text)
			_btn("sea_battle_sail").pressed.emit()
			_check(sb._hint_lbl.visible and sb._hint_lbl.text.contains("75 %"), "a sail change shows the hint: " + sb._hint_lbl.text)
			_shot("1_tooltip_bar")
			# A long press: button_down, then wait.
			_check(_btn("sea_douse") == null, "no Douse button while she is not burning")
			_btn("sea_chain").button_down.emit()
			_step = 1
			_frame = 0
		1:
			if _frame < 40:
				return false
			# (button_down was emitted without a real press: open the card as the timer would)
			sb._lp_swallow = true
			sb._open_help_card(sb.SeaBook.order_help("sea_chain", sb.sim.s_type[sb.selection[0]]))
			_check(sb._help_card != null and sb._help_card.is_inside_tree(), "the help card opens")
			_step = 2
			_frame = 0
		2:
			if _frame < 4:
				return false
			_shot("2_help_card")
			sb._close_help_card()
			_check(sb._help_card == null, "the help card closes")
			# Douse: set her alight (paused, so the fire holds); the bar shows the button with its tip.
			sb.speed_q = 0
			sb.sim.s_burn[sb.selection[0]] = 300
			_step = 20
			_frame = 0
		20:
			if _frame < 4:
				return false
			var db := _btn("sea_douse")
			_check(db != null and db.tooltip_text == "Douse: all hands to the buckets. Guns silent; the fire is fought twice as fast. Off by itself when the fire is out.",
				"burning, the bar shows Douse with its tip: " + (db.tooltip_text if db != null else "none"))
			if db != null:
				sb._lp_swallow = false  # (step 1 opened the help card by hand: no real release swallowed it)
				db.pressed.emit()
				sb.sim.step()
			_check(sb.sim.s_douse[sb.selection[0]] == 1 and int(sb.input_counts.get("douse", 0)) == 1,
				"a press douses her (s_douse %d, telemetry douse %d)" % [sb.sim.s_douse[sb.selection[0]], int(sb.input_counts.get("douse", 0))])
			_shot("1b_douse_bar")
			sb.speed_q = 4
			_step = 21
			_frame = 0
		21:
			if _frame < 4:
				return false
			sb.speed_q = 4
			sb._open_book()
			_check(sb.book.visible and sb.speed_q == 0, "the Ship book opens and pauses a solo battle")
			_step = 3
			_frame = 0
		3:
			var page := _frame / 8
			if _frame % 8 != 0:
				return false
			if page > 0:
				_shot("3_book_%d" % (page - 1))
			if page < sb.book.PAGES.size():
				sb.book.show_page(page)
				if sb.book.PAGES[page] == "Fire":
					var txt := ""
					for c in sb.book.find_children("*", "Label", true, false):
						txt += (c as Label).text + "\n"
					_check(txt.contains("Douse") and txt.contains("magazine") and txt.contains("0.5 %") and txt.contains("Don't lie alongside"),
						"the Fire page explains the start, the magazine, Douse and keeping clear")
				return false
			sb.book.show_page(sb.book.PAGES.find("Ships"))
			_check(sb.book.find_children("sea_book_ship_*", "", true, false).size() == ST.ROWS.size(), "the Ships page lists every row (%d)" % ST.ROWS.size())
			sb.book.close()
			_check(not sb.book.visible and sb.speed_q == 4, "closing the book resumes the speed")
			# The Key (owner 2026-10-22: "what the different coloured lines mean"): a bar button, a panel with a row and a
			# drawn sample for every kind in SeaKey.KINDS, the drawing code uses only those kinds, open / closed is remembered.
			var kb := _btn("sea_key_button")
			_check(kb != null and kb.tooltip_text != "", "the top bar has a Key button with a tip")
			var SK := preload("res://game/sea_key.gd")
			var was := SK.load_pref()
			sb._set_key(true)
			var kp: Control = sb.find_child("sea_key_panel", true, false)
			_check(kp != null and kp.visible and SK.load_pref(), "the Key opens and is remembered open")
			var missing: Array = []
			for id in SK.ids():
				var row: Node = kp.find_child("sea_key_row_" + str(id), true, false)
				if row == null or row.find_children("*", "Control", true, false).is_empty():
					missing.append(id)
			_check(missing.is_empty(), "the Key has a row with a sample for every kind (%d kinds; missing %s)" % [SK.ids().size(), missing])
			var src := FileAccess.get_file_as_string("res://game/sea_battle.gd")
			var used := {}
			for m in RegEx.create_from_string("SeaKey\\.col\\(\"([a-z]+)\"").search_all(src):
				used[m.get_string(1)] = true
			var stray: Array = []
			for k in used:
				if not SK.ids().has(k):
					stray.append(k)
			_check(not used.is_empty() and stray.is_empty(), "the drawing uses only Key kinds (%s; stray %s)" % [used.keys(), stray])
			var distinct := {}
			for id in ["attack", "board", "fire", "flee", "arcs", "wind"]:
				distinct[SK.col(id).to_html()] = true
			_check(distinct.size() == 6, "attack, boarding, fire ship, flee, guns and wind have six different colours")
			sb._set_key(false)
			_check(not kp.visible and not SK.load_pref(), "the Key closes and is remembered closed")
			SK.save_pref(was)
			_check(SK.hinted, "the first sea battle of the session pointed at the Key")
			print("RESULT: ", "PASS" if _ok else "FAIL")
			quit(0 if _ok else 1)
			return true
	return false
