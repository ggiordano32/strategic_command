extends Control
## The Ship book of the sea battle (game/sea_battle.gd): a full-screen overlay
## like the land battle's Unit book (list of pages on the left, Close), plus
## the help text of the orders bar (tooltips, the long-press card, the hint
## line). View only: it reads sim/sea_sim.gd and sim/sea_types.gd and never
## writes them; every number in a sentence comes from their constants or rows
## (nothing here is a rule of its own).
##
## Pages: Points of sail (a code-drawn polar diagram of drive() for a ship,
## wind from the top), Sails, Shot, Fighting (engaging, boarding, striking,
## fire ships), Fire (how a fire starts, the crew's fight, the magazine,
## Douse), Ships (every row of sim/sea_types.gd).

signal closed

const SeaSim := preload("res://sim/sea_sim.gd")
const ST := preload("res://sim/sea_types.gd")
const FM := preload("res://sim/fixed_math.gd")
const Kit := preload("res://game/campaign/ui_kit.gd")
const BTheme := preload("res://game/battle_theme.gd")
const TouchScroll := preload("res://game/touch_scroll.gd")

const PAGES := ["Points of sail", "Sails", "Shot", "Fighting", "Fire", "Galleys", "Ships"]
const KT := 1.94   # the status line's knots per unit (game/sea_battle.gd)

var sim: SeaSim = null
var ship := 0                       # the ship the wind rose is drawn for
var current := 0
var close_button: Button
var _list: Array[Button] = []
var _scroll: ScrollContainer
var _body: VBoxContainer
var _title: Label


func _init() -> void:
	name = "sea_book"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", Kit.trim_box(Color(Kit.PANEL_BG, 1.0), 14.0))
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 10
	panel.offset_top = 10
	panel.offset_right = -10
	panel.offset_bottom = -10
	add_child(panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	panel.add_child(row)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 6)
	list.custom_minimum_size = Vector2(150, 0)
	row.add_child(list)
	for i in PAGES.size():
		var b := Button.new()
		b.text = PAGES[i]
		b.name = "sea_book_page_%d" % i
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(150, 48)
		b.add_theme_font_size_override("font_size", 16)
		b.pressed.connect(show_page.bind(i))
		BTheme.plate(b, true)
		list.add_child(b)
		_list.append(b)
	var page := VBoxContainer.new()
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_theme_constant_override("separation", 8)
	row.add_child(page)
	var head := HBoxContainer.new()
	page.add_child(head)
	_title = Kit.title("Ship book", 22)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)
	close_button = Kit.button("Close", close, 90, 16)
	close_button.name = "sea_book_close"
	head.add_child(close_button)
	_scroll = TouchScroll.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_child(_scroll)
	_body = Kit.vbox(8)
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_body)


func open(p_sim: SeaSim, p_ship: int, page: int = -1) -> void:
	sim = p_sim
	ship = clampi(p_ship, 0, maxi(sim.n_units - 1, 0))
	visible = true
	show_page(current if page < 0 else page)


func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_ESCAPE:
				close()
			KEY_LEFT, KEY_UP:
				show_page((current + PAGES.size() - 1) % PAGES.size())
			KEY_RIGHT, KEY_DOWN:
				show_page((current + 1) % PAGES.size())
		get_viewport().set_input_as_handled()


func show_page(i: int) -> void:
	current = clampi(i, 0, PAGES.size() - 1)
	for k in _list.size():
		_list[k].set_pressed_no_signal(k == current)
	_title.text = "Ship book: " + PAGES[current]
	for c in _body.get_children():
		c.queue_free()
		_body.remove_child(c)
	match current:
		0:
			_page_sail()
		1:
			_page_sails()
		2:
			_page_shot()
		3:
			_page_fight()
		4:
			_page_fire()
		5:
			_page_galleys()
		6:
			_page_ships()
	_scroll.scroll_vertical = 0


func _p(text: String, col: Color = Color(0.9, 0.9, 0.88)) -> void:
	_body.add_child(Kit.label(text, 16, col, true))


func _h(text: String) -> void:
	_body.add_child(Kit.title(text, 18))


# ------------------------------------------------------------ the pages ---

func _page_sail() -> void:
	var ty := sim.s_type[ship]
	var irons := ST.stat(ty, "irons")
	var nm := ST.name_of(ty)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	_body.add_child(row)
	var rose := Control.new()
	rose.name = "sea_book_rose"
	rose.custom_minimum_size = Vector2(250, 250)
	rose.draw.connect(_draw_polar.bind(rose))
	row.add_child(rose)
	var col := Kit.vbox(6)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(col)
	col.add_child(Kit.label("Drive for a %s, wind from the top. The shape is the share of her top speed each heading gives (the ring is 100 %%); the red wedge is the no-go zone." % nm, 15, Color(0.85, 0.9, 0.95), true))
	if ST.stat(ty, "oars") != 0:
		col.add_child(Kit.label("Rowed ships ignore the wind: 100 % on every heading.", 15, Color.WHITE, true))
		return
	var f := func(deg: int) -> int:
		return sim.drive(ship, (sim.w_from + deg * FM.ANGLE_FULL / 360) & FM.ANGLE_MASK)
	col.add_child(Kit.label("Heading, degrees off the wind: drive", 15, Kit.COL_GOLD))
	var rows := [
		["0 to %d  (no-go zone, in irons)" % (irons - 1), "%d %%" % f.call(0)],
		["%d  (as close as she lies)" % irons, "%d %%" % f.call(irons)],
		["%d  (close-hauled)" % (irons + 14), "%d %%" % f.call(irons + 14)],
		["90  (beam reach)", "%d %%" % f.call(90)],
		["90 to 140  (reaching, the best)", "%d %%" % f.call(115)],
		["180  (running dead before it)", "%d %%" % f.call(180)],
	]
	for r in rows:
		var hb := Kit.hbox(8)
		var a := Kit.label(str(r[0]), 14, Color.WHITE, true)
		a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hb.add_child(a)
		hb.add_child(Kit.label(str(r[1]), 14, Kit.COL_GOLD))
		col.add_child(hb)
	_p("The wind: inside the no-go zone (%d degrees either side of the wind for a %s) a ship has no drive and slows to a stop. The navigator beats to windward in two tacks. She turns through the wind (tacks) when she carries at least %d %% of her top speed, else she wears round the other way, through downwind. Turning through the wind she carries her way round; head to wind and not turning she loses it in seconds, and a ship caught in irons without way falls off. The wind strength changes the speed too: a calm gives 45 %% of top speed, and each point of strength adds 0.7 %% up to a cap of 110 %%. The wind shifts a little every %d s." % [
		irons, nm, ST.stat(ty, "tack"), SeaSim.WIND_EVERY / 10])
	_p("Planning a course to a point: tap the sea and the course is drawn with its tacks. She keeps sea room: she starts each board on the tack with clear water ahead, tacks %d m short of land or the map edge, and within %d m of a shore to leeward she sails along it, never in toward it." % [
		SeaSim.LAYLINE_M, SeaSim.LEE_SHORE_M])
	_p("A ship sent to engage from far off takes the weather gauge only when she has it or can fetch it on one board, and then bears down to her range. From to leeward she makes for the enemy's lee bow, on a reach when she can, and never beats up past her. An enemy fleet to leeward of yours with you more than two boards to windward heaves to in line to receive you (for the first %d minutes), and comes to you after that." % [
		SeaSim.HOLD_TICKS / 600])


func _draw_polar(c: Control) -> void:
	var ctr := Vector2(125, 125)
	var r := 105.0
	c.draw_circle(ctr, r + 6, Color(0.05, 0.08, 0.1))
	c.draw_arc(ctr, r, 0, TAU, 48, Color(1, 1, 1, 0.45), 1.5, true)
	c.draw_arc(ctr, r * 0.5, 0, TAU, 32, Color(1, 1, 1, 0.18), 1.0, true)
	var ty := sim.s_type[ship]
	var irons := ST.stat(ty, "irons")
	# Headings from the top (0 = into the wind) round to the right and left.
	var pts := PackedVector2Array()
	var steps := 36
	var right := PackedVector2Array()
	for k in steps + 1:
		var deg := k * 180.0 / steps
		var d := sim.drive(ship, (sim.w_from + int(round(deg * FM.ANGLE_FULL / 360.0))) & FM.ANGLE_MASK)
		var ang := deg_to_rad(deg)
		right.append(Vector2(sin(ang), -cos(ang)) * (r * d / 100.0))
	pts.append(ctr)
	for p in right:
		pts.append(ctr + p)
	for k in range(right.size() - 1, -1, -1):
		pts.append(ctr + Vector2(-right[k].x, right[k].y))
	# The shape (a fan from the middle to the outline).
	for k in range(1, pts.size() - 1):
		c.draw_colored_polygon(PackedVector2Array([pts[0], pts[k], pts[k + 1]]), Color(0.35, 0.7, 0.9, 0.55))
	c.draw_polyline(pts, Color(0.6, 0.9, 1.0), 2.0, true)
	# The no-go wedge.
	var a0 := deg_to_rad(irons)
	var wedge := PackedVector2Array([ctr])
	for k in 13:
		var a := -a0 + 2.0 * a0 * k / 12.0
		wedge.append(ctr + Vector2(sin(a), -cos(a)) * r)
	c.draw_colored_polygon(wedge, Color(0.9, 0.25, 0.2, 0.45))
	for sgn in [-1.0, 1.0]:
		c.draw_line(ctr, ctr + Vector2(sin(a0) * sgn, -cos(a0)) * r, Color(1, 0.5, 0.4), 1.5, true)
	# The wind arrow, blowing down from the top.
	c.draw_line(Vector2(125, 2), Vector2(125, 30), Color(0.7, 0.9, 1.0), 3.0, true)
	c.draw_colored_polygon(PackedVector2Array([Vector2(125, 38), Vector2(118, 26), Vector2(132, 26)]), Color(0.7, 0.9, 1.0))
	# The ship in the middle.
	c.draw_colored_polygon(PackedVector2Array([ctr + Vector2(0, -9), ctr + Vector2(5, 7), ctr + Vector2(-5, 7)]), Color(0.95, 0.9, 0.8))
	var font := ThemeDB.fallback_font
	c.draw_string(font, Vector2(132, 14), "wind", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.7, 0.9, 1.0))
	c.draw_string(font, ctr + Vector2(-34, -r * 0.55), "no-go", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 0.7, 0.6))
	for e in [[irons + 14, "close"], [90, "beam"], [125, "broad"], [180, "run"]]:
		var ang := deg_to_rad(float(e[0]))
		var dd := sim.drive(ship, (sim.w_from + int(round(float(e[0]) * FM.ANGLE_FULL / 360.0))) & FM.ANGLE_MASK)
		var p := ctr + Vector2(sin(ang), -cos(ang)) * (r * dd / 100.0)
		c.draw_circle(p, 3.0, Color.WHITE)
		c.draw_string(font, p + Vector2(-70 if int(e[0]) == 90 else 5, 4 if e[0] != 180 else -4), "%s %d%%" % [e[1], dd], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)


func _page_sails() -> void:
	_p("Three sail settings, set per ship from the orders row. They change speed and nothing else: aim, reload and the guns are the same under any of them.")
	_h("Full sail  (%d %%)" % SeaSim.SAIL_PCT[2])
	_p("All the speed the wind and her rigging allow. Use it to close, to run, and to beat to windward.")
	_h("Battle sail  (%d %%)" % SeaSim.SAIL_PCT[1])
	_p("A quarter slower. Use it to hold your station near an enemy, or to match a slower ship so you can lie alongside.")
	_h("Heave to  (%d %%)" % SeaSim.SAIL_PCT[0])
	_p("Speed falls to nothing and she stops. Her guns still fire and reload as usual. A move order does not start her again: pick a sail setting.")
	_h("What else sets her speed")
	_p("Speed = her top speed x the points of sail (the Points of sail page) x the sail setting. Torn rigging slows her (full rigging 100 %, none left 25 %); so does a hull under half strength; so does a light wind. A rowed ship ignores the wind and slows as her crew thin (down to 30 % at no crew). A flee order and a fire ship's run set full sail themselves; a boarding ship trims her sail to match her prey.")


func _page_shot() -> void:
	var ty := gun_type(sim.s_type[ship])
	var nm := ST.name_of(ty)
	var gun := ST.stat(ty, "gun")
	_p("Each broadside (port and starboard) holds one shot kind, loaded at its next reload: the guns already loaded fire what they hold. The numbers below use a %s as the example (%d damage a hit); every ship has her own range." % [nm, gun])
	_h("Round shot  (range %d m)" % shot_range(ty, ST.SHOT_ROUND))
	_p("The hull. Each hit takes %d off her hull (she sinks at 0), kills about %.1f men with splinters, takes %d off the rigging, and each hit has a 0.5 %% chance to start a fire. Use it to sink or wear down a ship. Ships engaging with round shot lie about %d m off." % [gun, (gun + 2) / 5.0, gun / 4, SeaSim.RANGE_PREF[0]])
	_h("Chain shot  (range %d m, %d %% of round)" % [shot_range(ty, ST.SHOT_CHAIN), ST.CHAIN_RANGE_PCT])
	_p("The rigging. Each hit takes %d off her rigging (twice the shot weight) and 1 off her hull, and kills one man for every three hits. A ship with no rigging left sails at 25 %% speed, so use it to stop a ship running or before you board. Ships engaging with chain lie about %d m off." % [gun * 2, SeaSim.RANGE_PREF[1]])
	_h("Grape  (range %d m, %d %% of round)" % [shot_range(ty, ST.SHOT_GRAPE), ST.GRAPE_RANGE_PCT])
	_p("The crew. Each hit kills %d men and scratches the rigging; it hardly marks the hull. Grape hits 20 %% more often than round. Use it only at point-blank range: a broadside loaded with it cannot fire beyond that. Ships engaging with grape lie about %d m off." % [gun / 4 + 1, SeaSim.RANGE_PREF[2]])
	_h("Aim and raking")
	_p("A gun aimed at a 40 m ship hits about 88 % of the time at point-blank and 26 % at the edge of its range, scaled by the target's length (a 20 m sloop is a smaller mark) and by the gun crews' quality. The fewer the guns working (a battered hull works fewer, down to 40 %), the fewer the hits. Firing from ahead of her bow or astern, down her length (raking), kills 2 times the men with round shot, 1.5 with chain and 1.6 with grape.")
	_h("Reload")
	_p("A %s reloads a broadside in %d s with %d men to work the guns (%d a gun); with fewer, the reload slows in step, to 15 %% of its speed at worst. Changing the shot kind does not change the reload." % [nm, ST.stat(ty, "reload"), ST.stat(ty, "guns") * ST.MEN_PER_GUN * 2, ST.MEN_PER_GUN * 2])
	_h("Fire at will")
	_p("On: each broadside fires at the nearest enemy in its arc (%d degrees either side of abeam) and in range of its loaded shot, a ship ordered to engage first. Off (Hold fire): it fires only at the ship she was ordered to engage." % (SeaSim.ARC * 360 / FM.ANGLE_FULL))


func _page_fight() -> void:
	_h("Engaging")
	_p("Tap an enemy to engage her. Your ship sails to keep her broadside on at the range of the shot she holds (round %d m, chain %d m, grape %d m, never more than four fifths of her gun range). From far off she closes by the wind (the Points of sail page): from to windward she bears down, from to leeward she makes for the enemy's lee bow. Her guns fire as the target comes into the arc." % [SeaSim.RANGE_PREF[0], SeaSim.RANGE_PREF[1], SeaSim.RANGE_PREF[2]])
	_h("Boarding")
	_p("Arm Board, then tap an enemy (a struck ship too). She sails alongside, coming up under the stern when far. When the two ships' centres are within 40 %% of their lengths added together plus 8 m, and they are moving slowly relative to each other (or the target is nearly stopped), she grapples; both stop. A boarded ship is taken at once if she has struck. Otherwise the boarding party (%d %% of the boarder's crew and every soldier aboard) fights the defenders on the decks; the defenders, on their own deck, fight at %d %% strength. The defenders strike when their morale is gone or they are under %d %% of the boarders; the boarders are thrown back when theirs is gone or they are under %d %% of the defenders; if both crews are spent the ships part. Chain for a ship you mean to board (with her rigging gone she sails at a quarter speed and cannot run); round to sink her. Grape kills crew at short range only (%d %% of round shot's range), and a broadside loaded with it cannot fire beyond that, so it will not soften a ship as you close; the battle AI never loads it." % [
		SeaSim.DECK_BOARD_PCT, SeaSim.DECK_BONUS_PCT, SeaSim.DECK_BREAK_DEF, SeaSim.DECK_BREAK_ATT, ST.GRAPE_RANGE_PCT])
	_h("Striking")
	_p("Hits, losses and raking lower a ship's morale; quiet time restores it. She strikes her colours at 0 morale, or when her crew is under 18 % of its full number (or her hull under 12 % with her rigging under 25 %) and an enemy lies within 400 m. A struck ship stops and is out of the fight; the winner takes her when the battle is decided. A fire ship's crew never strike: they fire her.")
	_h("Ending")
	_p("The battle is decided when a side has no ship fighting (sunk, struck, taken or off the map edge), or after %d minutes by the fighting power left (a tie goes to the defender). Flee sets full sail for the map edge farthest from the enemy; a ship that leaves the map escapes and is out of the battle." % (SeaSim.TIME_LIMIT / 600))
	_h("Fire ships")
	_p("A fire ship (no guns) is sailed at an enemy and lit within %d m of her mark when she can lie the course; her crew take to the boat at %d m; what she touches is grappled and set alight and she burns down. Tap an enemy to send her in, or press Light her. Ships within %d m of a burning fire ship catch fire too. Fires and Douse: the Fire page." % [
		SeaSim.FS_LIGHT_M, SeaSim.FS_ABANDON_M, SeaSim.FS_SPREAD_M])


func _page_fire() -> void:
	var grow_lo := SeaSim.FIRE_GROW
	var grow_hi := SeaSim.FIRE_GROW + SeaSim.FIRE_GROW_ROLL
	var grow := SeaSim.FIRE_GROW + SeaSim.FIRE_GROW_ROLL / 2
	var fight := SeaSim.FIRE_FIGHT
	var douse := fight * SeaSim.DOUSE_FIGHT_PCT / 100
	_h("How a fire starts")
	_p("Each round shot hit has a %.1f %% chance to start a fire (4 times that on a fire ship); chain and grape never do. A fire ship sets alight whatever she touches (strength %d, and more every second she lies alongside), and sparks from her catch ships within %d m. A magazine blowing up sets each neighbour within %d m alight half the time." % [
		SeaSim.FIRE_PM / 10.0, SeaSim.FS_FIRE, SeaSim.FS_SPREAD_M, SeaSim.BLAST_M])
	_h("The crew's fight")
	_p("A fire has a strength from 1 to %d. Every second it grows by %d to %d (%d on average) and her crew beat it down by %d at full strength, less in step as the crew thin. A full crew puts a fresh fire (strength %d) out in about %d seconds; a crew under %d %% of its full number cannot keep up and the fire grows. While she burns the fire eats her hull by its strength: a full blaze takes 1 / %d of her hull a second, so she burns to the waterline in about %d minutes." % [
		SeaSim.FIRE_MAX, grow_lo, grow_hi, grow, fight, SeaSim.FIRE_START, (SeaSim.FIRE_START + fight - grow - 1) / maxi(fight - grow, 1),
		grow * 100 / fight + 1, SeaSim.FIRE_HULL / SeaSim.FIRE_MAX, SeaSim.FIRE_HULL / SeaSim.FIRE_MAX / 60])
	_h("The magazine")
	_p("Past strength %d each second may set off her magazine: the chance a second grows with the fire, %.1f %% at a full blaze. She blows up and is gone; every ship within %d m is holed, loses men and heart, and half the time catches fire herself." % [
		SeaSim.MAG_LV, (SeaSim.FIRE_MAX - SeaSim.MAG_LV) / float(SeaSim.MAG_DIV) / 10.0, SeaSim.BLAST_M])
	_h("Douse")
	_p("Douse (on the orders row while she burns): all hands to the buckets. Her guns go silent (they neither fire nor reload; a loaded broadside keeps its load) and the crew fight the fire at %d %%: %d a second at full strength, so even a crew down to %d %% gains on it. It turns off by itself the second the fire is out. Boarded while dousing, her men fight on the deck at %d %%. The battle AI douses too when a fire outgrows its crew." % [
		SeaSim.DOUSE_FIGHT_PCT, douse, grow * 100 / douse + 1, SeaSim.DOUSE_DECK_PCT])
	_h("Keep clear")
	_p("Don't lie alongside a burning ship: when her magazine goes, everything within %d m goes with her, and a fire ship's sparks jump to whatever is close. Board or rake a burning enemy from a distance, or let her burn." % SeaSim.BLAST_M)


func _page_galleys() -> void:
	_p("Rome's navy: the lembos, the trireme and the quinquereme (the Punic one has no corvus) fight with oars, ram and boarders, not guns. A galley ignores the wind: she rows at the same pace on every heading, and her pace falls with her crew (down to 30 % at none). She is lower in the water and turns sharper than a sailing ship. The Ships page lists each row's ram, marines and dash.")
	_h("The stroke")
	_p("The three sail buttons are the stroke. Rest: she lies on her oars. Cruise: %d %% of her top speed, as long as you like. Dash (ramming speed): full speed while the dash meter lasts. The meter holds each row's own number of seconds (the Ships page), drains one for every second at the dash and refills %d tenths of a second a second at cruise or rest; when it is empty she drops to cruise by herself. A tired crew does not start a ram run." % [
		SeaSim.CRUISE_PCT, SeaSim.DASH_FILL])
	_h("Ramming")
	_p("A ship with a ram that strikes an enemy hull with her bow (inside %d degrees either side of her heading), closing at %d or more (about %.1f m/s), does the ram's number x the closing speed / %d in hull damage; on the enemy's beam (within 45 degrees of square) it is doubled. Bow to bow, one blow of half the larger ram hurts both. The blow takes half the struck ship's way; the rammer backs water for %d s and cannot ram again for %d s. A push is not a ram: build up speed with the dash first. The battle AI sets up %d m off the target's beam and runs in at a right angle, dashing the last %d m." % [
		SeaSim.RAM_CONE * 360 / FM.ANGLE_FULL, SeaSim.RAM_MIN, SeaSim.RAM_MIN / 102.4, SeaSim.RAM_DIV, SeaSim.RAM_BACK / 10, SeaSim.RAM_COOL / 10, SeaSim.SETUP_M, SeaSim.RUN_M])
	_h("The corvus")
	_p("Rome's quinquereme carries the corvus, a boarding bridge. Within grappling range of an enemy, at a relative speed up to %d (about %.0f m/s), it drops and she boards at once, on firing at will or onto the ship she was ordered to engage. In that melee the boarders have the deck bonus (%d %%) and the defenders lose their home advantage. After her boarders are thrown back the bridge is hauled up for %d s. The Punic quinquereme has none: her boarders must wait for a low relative speed, as any ship's." % [
		SeaSim.CORVUS_REL, SeaSim.CORVUS_REL / 102.4, SeaSim.DECK_BONUS_PCT, SeaSim.CORVUS_COOL / 10])
	_h("Missiles")
	_p("A galley's marines (not the rowers) throw javelins and arrows every reload (8 s) at the nearest enemy within %d m: a few men killed and morale knocked, which is all the exchange before the ships meet. A lembos without a ram engages at %d m and boards the weak; a larger ship will crush her, so the AI keeps her clear of ships over twice her hull unless they are crippled." % [
		SeaSim.MSL_M, SeaSim.MSL_STAND])
	_h("Orders")
	_p("Dash, Cruise and Rest set the stroke. At will lets the corvus drop on the nearest enemy as well; Hold keeps it for the ordered target. Board and Flee as for any ship (a fleeing galley rows straight away from the nearest enemy, not downwind). There is no shot to choose: the shot buttons are hidden for galleys.")


func _page_ships() -> void:
	_p("Every ship row, from the battle's own table. Speeds are in the status line's knots at full sail on the best heading; turn is degrees a second; tack is the share of top speed she needs to go through the wind.")
	for i in ST.ROWS.size():
		var r: Dictionary = ST.row(i)
		var p := Kit.panel(Color(0.14, 0.17, 0.18, 1.0), 8)
		p.name = "sea_book_ship_%s" % str(r["key"])
		var v := Kit.vbox(3)
		p.add_child(v)
		v.add_child(Kit.title("%s  (%d m long)" % [str(r["name"]), int(r["len"])], 18))
		var lines: Array[String] = []
		if ST.is_fire(i):
			lines.append("No guns. Crew %d, hull %d, rigging %d. Sailed at an enemy and lit near her; boarding quality %d %%." % [int(r["crew"]), int(r["hull"]), int(r["rig"]), int(r["board"])])
		elif ST.is_galley(i):
			var gl := "No guns. Crew %d, hull %d. Boarding quality %d %%." % [int(r["crew"]), int(r["hull"]), int(r["board"])]
			if int(r["ram"]) > 0:
				gl += " Ram %d" % int(r["ram"])
				if int(r["corvus"]) != 0:
					gl += " and the corvus"
				gl += "."
			elif int(r["corvus"]) != 0:
				gl += " The corvus."
			if int(r["marines"]) > 0:
				gl += " %d marines." % int(r["marines"])
			if int(r["dash"]) > 0:
				gl += " Ramming speed for %d s." % int(r["dash"])
			lines.append(gl)
		elif int(r["guns"]) == 0:
			lines.append("No guns. Crew %d, hull %d, rigging %d. A merchantman: she carries cargo and men, and fights by boarding (quality %d %%)." % [int(r["crew"]), int(r["hull"]), int(r["rig"]), int(r["board"])])
		else:
			lines.append("Guns %d a side, %d damage a hit, reload %d s. Range: round %d m, chain %d m, grape %d m." % [
				int(r["guns"]), int(r["gun"]), int(r["reload"]), int(r["range"]),
				int(r["range"]) * ST.CHAIN_RANGE_PCT / 100, int(r["range"]) * ST.GRAPE_RANGE_PCT / 100])
			lines.append("Crew %d, hull %d, rigging %d. Boarding quality %d %%." % [int(r["crew"]), int(r["hull"]), int(r["rig"]), int(r["board"])])
		var mv := "Top speed %.1f kn, turns %.1f degrees a second." % [int(r["vmax"]) / 10.0 * KT, int(r["turn"]) / 10.0]
		if int(r["oars"]) != 0:
			mv += " Rowed: the wind does not drive her; speed falls with her crew." + (" Cruises at %d %% of top speed." % SeaSim.CRUISE_PCT if ST.is_galley(i) else "")
		else:
			mv += " No-go zone %d degrees either side of the wind; tacks at %d %% of top speed." % [int(r["irons"]), int(r["tack"])]
		mv += " " + ("Deep draught: runs aground on shoals." if int(r["draft"]) != 0 else "Shallow draught: crosses shoals.")
		lines.append(mv)
		for t in lines:
			v.add_child(Kit.label(t, 14, Color(0.9, 0.9, 0.88), true))
		_body.add_child(p)


# -------------------------------------------------- the orders bar's help ---

## The help of one order button: {"title", "tip" (one line), "more" (one more
## line of context), "hint" (shown for 3 s when a sail or shot setting
## changes; "" for the other orders)}. `ship_type` is the first selected ship's
## row (the shot ranges are hers; a fire ship, with no guns, shows a frigate's).
static func order_help(key: String, ship_type: int, fire_on: bool = true) -> Dictionary:
	var ty := gun_type(ship_type)
	var nm := ST.name_of(ty)
	var gun := ST.stat(ty, "gun")
	var rd := shot_range(ty, ST.SHOT_ROUND)
	var ch := shot_range(ty, ST.SHOT_CHAIN)
	var gr := shot_range(ty, ST.SHOT_GRAPE)
	if ST.is_galley(ship_type) and ["sea_full", "sea_battle_sail", "sea_stop", "sea_fire"].has(key):
		# (R2) A galley's sail settings are her stroke.
		match key:
			"sea_full":
				return {"title": "Dash", "tip": "Dash: ramming speed, 100 % of her top speed while the dash meter lasts, then she drops to cruise. Use it for the last run at a ram target.",
					"more": "The meter drains while she dashes and refills at cruise or rest. A tired crew does not start a ram run. The wind does not matter to a galley.",
					"hint": "Dash: ramming speed while the meter lasts."}
			"sea_battle_sail":
				return {"title": "Cruise", "tip": "Cruise: %d %% of her top speed, for as long as you like; the dash meter refills. Use it to close and to hold station." % SeaSim.CRUISE_PCT,
					"more": "A rowed ship ignores the wind; her pace falls only with her crew.",
					"hint": "Cruise: %d %% speed, the dash meter refills." % SeaSim.CRUISE_PCT}
			"sea_stop":
				return {"title": "Rest", "tip": "Rest: oars shipped, speed falls to 0. A move order does not start her again: pick cruise or dash.",
					"more": "Resting refills the dash meter. The marines still throw their javelins.",
					"hint": "Rest: speed 0, the dash meter refills."}
			_:
				return {"title": ("At will" if fire_on else "Hold"), "tip": "At will: the corvus drops on the nearest enemy within reach; Hold: only on the ship she was ordered to engage. Press it to change.",
					"more": "Rams and missiles work either way. A galley with no corvus has nothing to hold.",
					"hint": "At will: the corvus drops on any enemy within reach." if fire_on else "Hold: the corvus drops only on her ordered target."}
	match key:
		"sea_full":
			return {"title": "Full sail", "tip": "Full sail: 100 % of the speed the wind allows. Use it to close, to run and to beat to windward.",
				"more": "The sail setting changes speed only; aim and reload are the same. Torn rigging, a light wind and a battered hull slow her too.",
				"hint": "Full sail: 100 % speed. The guns are not affected."}
		"sea_battle_sail":
			return {"title": "Battle sail", "tip": "Battle sail: %d %% speed. Use it to hold your station near an enemy or to match a slower ship." % SeaSim.SAIL_PCT[1],
				"more": "The sail setting changes speed only; aim and reload are the same.",
				"hint": "Battle sail: %d %% speed. The guns are not affected." % SeaSim.SAIL_PCT[1]}
		"sea_stop":
			return {"title": "Heave to", "tip": "Heave to: speed falls to 0 and she stops; the guns still fire and reload. Use it to sit still while the guns work.",
				"more": "A move order does not start her again: pick full or battle sail.",
				"hint": "Hove to: speed 0 %. The guns still fire and reload."}
		"sea_round":
			return {"title": "Round shot", "tip": "Round shot: breaks the hull (%d a hit) and kills a few by splinters; may start a fire. Range %d m (%s). Use it to sink a ship." % [gun, rd, nm],
				"more": "Ships engaging with round shot lie about %d m off. Loaded at the next reload; guns already loaded keep the old shot. Raking (from ahead or astern) kills twice the men." % SeaSim.RANGE_PREF[0],
				"hint": "Round shot: hull and splinters, range %d m. Loaded at the next reload." % rd}
		"sea_chain":
			return {"title": "Chain shot", "tip": "Chain shot: cuts rigging, slows her (range %d m, %s). Use it to stop a ship running or before boarding." % [ch, nm],
				"more": "Each hit takes %d off her rigging; with none left she sails at 25 %% speed. Ships engaging with chain lie about %d m off. Loaded at the next reload." % [gun * 2, SeaSim.RANGE_PREF[1]],
				"hint": "Chain shot: rigging and speed, range %d m. Loaded at the next reload." % ch}
		"sea_grape":
			return {"title": "Grape", "tip": "Grape: kills crew at short range (%d m, %s), little harm to the hull. Use it only at point-blank range; a loaded broadside cannot fire further." % [gr, nm],
				"more": "Each hit kills %d men and hits 20 %% more often than round. Ships engaging with grape lie about %d m off. Loaded at the next reload." % [gun / 4 + 1, SeaSim.RANGE_PREF[2]],
				"hint": "Grape: crew only, range %d m. Loaded at the next reload." % gr}
		"sea_fire":
			if fire_on:
				return {"title": "Fire at will", "tip": "Fire at will is on: each broadside fires at the nearest enemy in its arc and range. Press it for Hold fire.",
					"more": "The arc is %d degrees either side of abeam. The ship she was ordered to engage is shot at first." % (SeaSim.ARC * 360 / FM.ANGLE_FULL), "hint": ""}
			return {"title": "Hold fire", "tip": "Hold fire: she fires only at the ship she was ordered to engage. Press it for Fire at will.",
				"more": "With no engage order her guns stay quiet. Use it to keep her fire on one target.", "hint": ""}
		"sea_board":
			return {"title": "Board", "tip": "Board: then tap an enemy. She lays alongside and grapples; the crews fight on the decks. Use it on a crippled or struck ship.",
				"more": "%d %% of her crew and every soldier go across. The defenders strike when they fall under %d %% of the boarders. A struck ship is taken at once." % [SeaSim.DECK_BOARD_PCT, SeaSim.DECK_BREAK_DEF], "hint": ""}
		"sea_hold":
			return {"title": "Hold course", "tip": "Hold course: drops her order (sail to, engage, board); she keeps her heading. Use it to take her off a course you no longer want.",
				"more": "Her sail setting and shot stay as they are.", "hint": ""}
		"sea_flee":
			return {"title": "Flee", "tip": "Flee: full sail for the map edge farthest from the enemy. A ship that leaves the map escapes and is out of the battle.",
				"more": "Use it for a ship that cannot win; she can still be hit on the way out.", "hint": ""}
		"sea_douse":
			return {"title": "Douse", "tip": "Douse: all hands to the buckets. Guns silent; the fire is fought twice as fast. Off by itself when the fire is out.",
				"more": "Loaded guns keep their load. Boarded while dousing, her men fight on the deck at %d %%. Press it again to send the crew back to the guns." % SeaSim.DOUSE_DECK_PCT,
				"hint": ""}
		"sea_light":
			return {"title": "Light her", "tip": "Light her: sets the fire ship alight now; her crew take to the boat and she burns down. Tap an enemy instead to send her in.",
				"more": "A sent-in fire ship lights herself within %d m of her mark when she can lie the course. What she touches is grappled and set alight." % SeaSim.FS_LIGHT_M, "hint": ""}
		"sea_gift":
			return {"title": "Gift", "tip": "Gift: hands the selected ships to a team-mate, who then commands them.", "more": "", "hint": ""}
	return {"title": "", "tip": "", "more": "", "hint": ""}


## The row whose guns the help quotes: the ship's own, or a frigate's for a
## ship without guns (a fire ship).
static func gun_type(ty: int) -> int:
	if ST.stat(ty, "guns") > 0:
		return ty
	return maxi(ST.index_of("frigate"), 0)


## Range of a shot kind for row ty (sim/sea_sim.gd shot_range, from the row).
static func shot_range(ty: int, shot: int) -> int:
	var r := ST.stat(ty, "range")
	if shot == ST.SHOT_CHAIN:
		return r * ST.CHAIN_RANGE_PCT / 100
	if shot == ST.SHOT_GRAPE:
		return r * ST.GRAPE_RANGE_PCT / 100
	return r
