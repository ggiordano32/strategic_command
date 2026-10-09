extends Control
## The unit book: a full-screen overlay listing every unit type, with one
## UnitEntry page shown at a time (list on the left, Previous / Next, Close),
## and two last pages, "Terrain" (with woods) and "Settlements and sieges",
## explaining those rules with the sim's own numbers. Used from the start menu and from the battle HUD; it only
## emits `closed` and never touches the sim.

signal closed

const TouchScroll := preload("res://game/touch_scroll.gd")
const UT := preload("res://sim/unit_types.gd")
const Icons := preload("res://game/unit_icons.gd")
const IconView := preload("res://game/unit_icon_view.gd")
const UnitEntry := preload("res://game/unit_entry.gd")
const BattleSim := preload("res://sim/battle_sim.gd")
const MapGen := preload("res://sim/mapgen.gd")
const CBattleL := preload("res://campaign/cbattle.gd")

var entry: UnitEntry
## Page shown: a unit type, UT.count() for the Terrain page, UT.count() + 1
## for Settlements and sieges.
var current := 0
var terrain_page: ScrollContainer
var terrain_text: Label
var side_color := Color(0.35, 0.6, 1.0)
var _list: Array[Button] = []
var prev_button: Button
var next_button: Button
var close_button: Button


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.1, 0.12, 0.1, 1.0)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(12)
	panel.add_theme_stylebox_override("panel", sb)
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 10
	panel.offset_top = 10
	panel.offset_right = -10
	panel.offset_bottom = -10
	add_child(panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	panel.add_child(row)
	# Unit list.
	var lscroll := TouchScroll.new()
	lscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	lscroll.custom_minimum_size = Vector2(210, 0)
	row.add_child(lscroll)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 6)
	lscroll.add_child(list)
	for ty in UT.count():
		var b := Button.new()
		b.custom_minimum_size = Vector2(200, 56)
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.text = "            " + str(UT.TYPES[ty]["name"])
		b.add_theme_font_size_override("font_size", 16)
		var ic := IconView.new(Icons.icon_of(ty), side_color, 40.0)
		ic.position = Vector2(8, 8)
		b.add_child(ic)
		b.pressed.connect(show_type.bind(ty))
		list.add_child(b)
		_list.append(b)
	var tb := Button.new()
	tb.custom_minimum_size = Vector2(200, 56)
	tb.toggle_mode = true
	tb.focus_mode = Control.FOCUS_NONE
	tb.text = "Terrain"
	tb.add_theme_font_size_override("font_size", 16)
	tb.pressed.connect(show_type.bind(UT.count()))
	list.add_child(tb)
	_list.append(tb)
	var sb2 := Button.new()
	sb2.custom_minimum_size = Vector2(200, 56)
	sb2.toggle_mode = true
	sb2.focus_mode = Control.FOCUS_NONE
	sb2.text = "Settlements and sieges"
	sb2.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sb2.add_theme_font_size_override("font_size", 16)
	sb2.pressed.connect(show_type.bind(UT.count() + 1))
	list.add_child(sb2)
	_list.append(sb2)
	# Page with its header.
	var page := VBoxContainer.new()
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_theme_constant_override("separation", 8)
	row.add_child(page)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	page.add_child(head)
	var title := Label.new()
	title.text = "Unit book"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	prev_button = _button("< Prev")
	prev_button.pressed.connect(func(): show_type((current + _pages() - 1) % _pages()))
	head.add_child(prev_button)
	next_button = _button("Next >")
	next_button.pressed.connect(func(): show_type((current + 1) % _pages()))
	head.add_child(next_button)
	close_button = _button("Close")
	close_button.pressed.connect(close)
	head.add_child(close_button)
	entry = UnitEntry.new()
	page.add_child(entry)
	terrain_page = TouchScroll.new()
	terrain_page.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	terrain_page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	terrain_page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	terrain_page.visible = false
	page.add_child(terrain_page)
	terrain_text = Label.new()
	terrain_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	terrain_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	terrain_text.add_theme_font_size_override("font_size", 16)
	terrain_text.text = terrain_help()
	terrain_page.add_child(terrain_text)


func _pages() -> int:
	return UT.count() + 2


## The Terrain page, in plain words, with the numbers the sim uses.
static func terrain_help() -> String:
	var climb := "%d%% (light infantry, javelins) to %d%% (pikes), cavalry %d%%" % [
		UT.stat(UT.LIGHT, "climb"), UT.stat(UT.PIKE, "climb"), UT.stat(UT.CAVALRY, "climb")]
	var lines: Array[String] = [
		"TERRAIN",
		"",
		"Reading the ground. The field is drawn like a contour map: each thin line is 2 m higher or lower than the next, every fifth line is a little darker, slopes facing the light (upper left) are lighter and slopes facing away darker, and higher ground is slightly paler. Lines close together mean a steep slope. The faint grid squares are 50 m.",
		"",
		"Moving. Each 10%% of uphill slope costs a unit some of its speed: %s, packed artillery %d-%d%%. A slope of 10%% rises 1 m in 10 m. Never slower than %d%% of normal (artillery %d%%). A gentle downhill (up to 10%%) is up to %d%% faster; downhill steeper than %d%% slows again (cavalry twice as much). Moving across ground steeper than %d%% loosens a formation: a pike block's wall comes down and spearmen cannot brace until they stand again." % [
			climb, UT.stat(UT.BOLT, "climb"), UT.stat(UT.STONE, "climb"), BattleSim.TER_MIN_FAC / 10,
			BattleSim.TER_MIN_FAC_ART / 10, BattleSim.TER_DOWN_BONUS / 10,
			(BattleSim.TER_STEEP * 100 + 2048) / 4096, (BattleSim.TER_STEEP * 100 + 2048) / 4096],
		"",
		"Fighting. A man striking down at his opponent hits a little more often: +%.1f%% for each 10%% of slope between them, at most +%.0f%%, and the man below hits that much less. Small per blow, but a long fight adds it up: between two equal units a moderate slope (10-15%%) is worth roughly a 60-70%% chance of winning to the side above, a steep one (25%%) about 85%%. Never a sure thing." % [
			BattleSim.MELEE_H_K / 100.0, BattleSim.MELEE_H_CAP / 10.0],
		"",
		"Charging. Cavalry riding down onto a man hits harder (+%d%% per 10%% of slope, at most +%d%%); riding up into him, weaker (down to -%d%%). Uphill the horses cannot build a full charge at all: on a 20%% climb only a weak one. A good downhill run builds momentum faster." % [
			BattleSim.CHG_H_K / 10, BattleSim.CHG_H_MAX - 100, 100 - BattleSim.CHG_H_MIN],
		"",
		"Shooting. From higher ground missiles reach further, and shooting uphill they fall short by as much: arrows and stones %.1f m for each metre of height, javelins %.1f m, bolts %.1f m (at most %d%% of the range). The range ring of a selected unit bends to show this. Arrows and stones arc over hills; javelins and bolts fly flat and cannot shoot through a crest. A target hidden by the ground is shown with a broken red line and a cross where the ground gets in the way; javelin units ordered to shoot it walk closer until they can. A bolt is stopped by rising ground and flies over the heads of men below its line." % [
			UT.stat(UT.ARCHER, "m_hgain") / 100.0, UT.stat(UT.JAVELIN, "m_hgain") / 100.0,
			UT.stat(UT.BOLT, "m_hgain") / 100.0, BattleSim.RANGE_H_CAP],
		"",
		"Stones bounce on %d%% less far for each 10%% they land uphill, and %d%% further downhill." % [
			BattleSim.STONE_UP_K / 10, BattleSim.STONE_DOWN_K / 10],
		"",
		"Pikes. A pike block standing on ground steeper than %d%% loses its order %d%% faster when struck in the flank, the rear or by a charge." % [
			(BattleSim.TER_STEEP * 100 + 2048) / 4096, BattleSim.PIKE_STEEP_DIS - 100],
		"",
		"The enemy. The AI deploys on nearby higher ground, stops on a crest while its archers shoot, holds a hill it stands on (up to 4 minutes, unless outshot) and lets you climb to it, goes round to a gentler side rather than straight up a steep slope, avoids charging uphill, and puts its archers and engines on rises with a clear line of fire.",
		"",
		"Ordered moves and attacks show 'uphill' or 'downhill' with the average slope when it is 4% or more.",
		"",
		woods_help(),
	]
	return "\n".join(lines)


static func _pcts(a: Array) -> String:
	return "%d / %d / %d%%" % [a[1], a[2], a[3]]


## Speed in light / medium / dense woods for a class row of VEG_SPEED.
static func _speeds(row: int) -> String:
	var a: Array = BattleSim.VEG_SPEED[row]
	return "%d / %d / %d%%" % [int(a[1]) / 10, int(a[2]) / 10, int(a[3]) / 10]


## The woods section of the Terrain page.
static func woods_help() -> String:
	var lines: Array[String] = [
		"WOODS",
		"",
		"Woods are drawn as trees: scattered ones are light woods, a closed canopy dense woods. Treetops fade where soldiers stand under them. A move order shows where its line runs through trees (green), the formation preview marks the men who would stand in woods, and the hint says 'woods' or 'dense woods'.",
		"",
		"Moving. In light / medium / dense woods a unit keeps this much of its speed: infantry %s, pikes %s, missile troops %s, cavalry %s, artillery %s. A battery cannot set up in dense woods." % [
			_speeds(0), _speeds(1), _speeds(2), _speeds(3), _speeds(4)],
		"",
		"Formations. Moving through woods loosens a formation: disorder grows by %d / %d / %d a tick (it fades by 2 a tick) up to %d / %d / %d. From %d a pike block drops its wall and spearmen cannot brace; a pike block cannot stand formed in medium or dense woods at all." % [
			BattleSim.VEG_DIS_GAIN[1], BattleSim.VEG_DIS_GAIN[2], BattleSim.VEG_DIS_GAIN[3],
			BattleSim.VEG_DIS_CAP[1], BattleSim.VEG_DIS_CAP[2], BattleSim.VEG_DIS_CAP[3], BattleSim.DISORDERED],
		"",
		"Charges. Cavalry in woods cannot build a full charge: momentum is capped at %s of a full charge (a charge needs %d to strike at all). A charge into men standing in woods hits at %s of its force." % [
			_pcts(BattleSim.VEG_MOM_CAP), BattleSim.CHARGE_MIN, _pcts(BattleSim.VEG_IMPACT)],
		"",
		"Missiles. The trees catch %s of the arrows, %s of the javelins and %s of the stones that come down in light / medium / dense woods (so men in woods are harder to hit); a stone that gets through rolls %d / %d / %d%% as far. Javelins and bolts fly flat: woods between the thrower and the target add up (light %d, medium %d, dense %d per 4 m) and past %d block the shot - about %d m of dense woods. A target behind them is shown with the broken red line." % [
			_pcts(BattleSim.VEG_STOP_ARROW), _pcts(BattleSim.VEG_STOP_JAV), _pcts(BattleSim.VEG_STOP_STONE),
			BattleSim.VEG_PLOUGH[1] / 10, BattleSim.VEG_PLOUGH[2] / 10, BattleSim.VEG_PLOUGH[3] / 10,
			BattleSim.TREE_W[1], BattleSim.TREE_W[2], BattleSim.TREE_W[3], BattleSim.TREE_BLOCK,
			BattleSim.TREE_BLOCK * 4 / BattleSim.TREE_W[3] + 4],
		"",
		"Morale is not affected by woods. Woods are as dense as the region: Gaul and northern Italy are wooded, Africa and the south-east of Iberia nearly bare.",
	]
	return "\n".join(lines)


## The Settlements and sieges page.
static func siege_help() -> String:
	var hp: Array = MapGen.GATE_HP
	var wh: Array = MapGen.WALL_H
	var lines: Array[String] = [
		"SETTLEMENTS AND SIEGES",
		"",
		"Every settlement is fought over on its own map: houses and streets round a plaza, and with walls a ring of wall and towers with gates. Each city keeps the same map for good (its seed is fixed when the campaign starts), so you can learn it; the region panel shows it with 'View battle map'. A village is %d m across, a town %d m, a city %d m; the map changes as the settlement grows and its walls are built up." % [
			MapGen.R_LEVEL[0] * 2, MapGen.R_LEVEL[1] * 2, MapGen.R_LEVEL[2] * 2],
		"",
		"Plans. A settlement keeps the plan of the people who founded it, whoever holds it now. Roman (Latin) towns are a rectangle with square towers and four gates at the ends of two main streets that cross at the forum. Greek cities follow the ground, with the agora off the centre, blocks at an angle and a walled acropolis on the highest corner. Punic cities have a thick wall with close square towers, only two land gates, dense blocks and a walled citadel inland. Celtic oppida are an oval on a rise whose main gate stands at the end of a funnel in the wall, so men at it are shot from both sides; villages and oppida keep gardens, pens and orchards inside the wall, open ground to cross under fire. The owner's banners fly on the gates, the citadel and the plaza, its shrine stands on the plaza, and what it builds is in its own style.",
		"",
		"Sites. On a plain the town is open on all sides, with a straight road and orchards before the main gate; at wall level 3 a ditch %d m wide runs round it %d m out from the towers: foot cross it slowly (%d%% speed), horses and engines only by the causeways in front of the gates. On a hill the town rises up a slope that is gentle on the side of the main gate and steeper elsewhere. On a spur it stands on a tongue of high ground, steep on three sides, reached by one level neck to the main gate; its other gates are narrow posterns. A port has the sea behind it: nobody walks on the water (missiles fly over it), the sea gate and the mole are only scenery, the attackers come from the land, and routed or withdrawing defenders get away along the shore." % [
			MapGen.DITCH_W, MapGen.DITCH_GAP, BattleSim.DITCH_SPEED / 10],
		"",
		"Streets. Houses and walls cannot be crossed: units find their way along the streets and through the gates by themselves, and a unit too wide for a street closes up its files and opens out again after. In a street a formed block cannot be flanked; cavalry in the streets cannot build a charge (at most %d%% of a full charge)." % BattleSim.URBAN_MOM_CAP,
		"",
		"Walls. Level 1 / 2 / 3 walls are %d / %d / %d m thick and their walkway %d / %d / %d m high. Attackers climb them only with ladders (see Siege equipment); otherwise the way in is through a gate. The defenders' missile troops start on the walls near the gates: from there they shoot further (height) and over the wall, %d / %d / %d%% further at men below, and %d / %d / %d%% of the missiles shot up at them are stopped by the battlements (level 1 / 2 / 3). Each stretch of walkway has a stair at both ends. A defending foot or missile unit sent onto a wall (tap the walkway, the wall itself or a tower, or press Man the wall: the stretch within 60 m nearest the enemy) marches to the better stair and climbs; it stands there in two ranks along the walkway, and a unit too long for its stretch goes on through the tower onto the next one. A move along its own stretch slides it along; anywhere else (or Come down) takes it down a stair and on through the streets in its normal block. The way up or down and the stair are drawn when you give the order. Attackers, cavalry, pikes and engines cannot man walls. Men who break on a wall leave it by the nearest stair. Walls and houses stop javelins and bolts; arrows and stones fly over them." % [
			MapGen.WALL_T[1], MapGen.WALL_T[2], MapGen.WALL_T[3], wh[1], wh[2], wh[3], BattleSim.WALL_RANGE_PCT[1],
			BattleSim.WALL_RANGE_PCT[2], BattleSim.WALL_RANGE_PCT[3], BattleSim.WALL_COVER[1], BattleSim.WALL_COVER[2], BattleSim.WALL_COVER[3]],
		"",
		"Gates. Up to %d / %d / %d gates for wall level 1 / 2 / 3 (a village has at most 2, a town 3). A gate has %d / %d / %d hit points by wall level and starts shut. The defenders open or shut a gate by tapping it (with nothing selected); it can only be shut when nobody stands in it, and a broken gate stays open. To break one, select engines or foot and tap it: a bolt that hits it takes off %d, a stone %d; foot go to its face and hack at it, each man taking off (weapon damage - %d) x %d%% per swing at a level 1 gate, at most %d men at a time (heavy swordsmen: a level 1 gate in roughly a minute); level 2 and 3 gates are bound with iron and do not yield to swords at all: a ram or engines break them, and foot are not sent at them. Cavalry and missile troops cannot break a gate." % [
			4, 3, 2, hp[1] * BattleSim.GATE_HP_PCT[1] / 100, hp[2] * BattleSim.GATE_HP_PCT[2] / 100,
			hp[3] * BattleSim.GATE_HP_PCT[3] / 100, BattleSim.GATE_BOLT, BattleSim.GATE_STONE, BattleSim.GATE_ARMOUR,
			BattleSim.GATE_HACK_BY_WALLS[1], BattleSim.GATE_HACKERS],
		"",
		"Towers. A level 2 city mounts bolt throwers on up to %d of its towers (by the gates first), a level 3 city %d, and two stone throwers on its biggest towers as well. They are the defenders' units: they never move or break, shoot the ram, batteries and men at the gates or on ladders, carry a fixed load of shots (half as many again with a Workshop in the city), and fall silent when their crew is shot down or their tower is battered (enemy engines ordered at a tower: a stone takes off %d, a bolt %d)." % [
			BattleSim.TOWERS_MAX[2], BattleSim.TOWERS_MAX[3], BattleSim.TOWER_STONE_DMG, BattleSim.TOWER_BOLT_DMG],
		"",
		"Siege equipment. Sets of ladders and the ram lie behind the attackers' line at the start (in the campaign an army that has besieged a city for a turn has %d sets of ladders, after two turns %d and a ram; storming on arrival it has only its own engines; custom battles and the sandbox choose). Any foot unit picks a piece up: select it and tap the piece. Carrying it, the unit walks (ladders a little slower, the ram at %d.%d m/s), never runs, attacks nobody and defends itself poorly; Drop (X) puts it down where it stands, free to fight, and any foot unit can pick it up again; routed carriers leave it behind. Ladders: tap a stretch of the wall from outside with the carriers selected: they march to its foot, plant the five ladders there (for the battle) and climb; any other foot (not pikes) ordered onto that stretch climbs there too. A man goes up each ladder every %d / %d / %d seconds (wall level 1 / 2 / 3), under fire from the walls and towers all the while; the men arrive on the walkway one at a time and fight the defenders there; once all are up, tap a gate to send them down into the town to unbar it from inside (%d men there for %d seconds open it). The ram: tap a gate with its carriers selected (an outer gate, or the citadel's from the town): at its face up to %d of them batter it (%d hit points a blow, a blow every few seconds) and put it down when it breaks; its roof keeps most arrows off them; tower bolts and stones can wreck it (%d hit points), and defenders standing at a ram left on the ground smash it." % [
			int(CBattleL.LADDER_SETS[0]), int(CBattleL.LADDER_SETS[1]), BattleSim.RAM_WALK * 10 / 1024, BattleSim.RAM_WALK * 100 / 1024 % 10,
			BattleSim.LADDER_TICKS[1] / 10, BattleSim.LADDER_TICKS[2] / 10, BattleSim.LADDER_TICKS[3] / 10,
			BattleSim.UNBAR_MEN, BattleSim.UNBAR_TICKS / 10, BattleSim.RAM_CREW, BattleSim.RAM_DMG, BattleSim.RAM_HP],
		"",
		"Siege towers. Against walls 2-3, an army that has besieged the city for %d turns brings a rolling siege tower, after %d turns two (custom battles: Siege towers). They start at the attackers' edge. A foot unit pushes one (select it, tap the tower): at most %d.%d m/s with %d men or more, slower with fewer; it never runs, and the tower's roof keeps most arrows off the men behind it. Tap a stretch of wall with them selected: they push it to the wall, plant it (for the battle) and cross onto the walkway over its ramp, %d men abreast, a man a lane every %d.%d seconds whatever the walls' height; any foot unit (not pikes) ordered onto that stretch crosses it too, the enemy's as well. Drop (X) leaves it where it stands and anyone, the defenders too, may push it away; a planted tower stays. It is wooden (%d hit points): fire missiles set it burning, tower bolts and stones batter it, men standing at it on the ground smash it; when a planted tower falls the men still on it come back down." % [
			int(CBattleL.TOWER_TURNS[0]), int(CBattleL.TOWER_TURNS[1]), BattleSim.EQ_PACE[BattleSim.EQ_TOWER] * 10 / 1024,
			BattleSim.EQ_PACE[BattleSim.EQ_TOWER] * 100 / 1024 % 10, BattleSim.EQ_MEN[BattleSim.EQ_TOWER],
			BattleSim.EQ_LANES[BattleSim.EQ_TOWER], BattleSim.EQ_CLIMB[BattleSim.EQ_TOWER] / 10,
			BattleSim.EQ_CLIMB[BattleSim.EQ_TOWER] % 10, BattleSim.EQ_HP[BattleSim.EQ_TOWER]],
		"",
		"Taking the city. Besides breaking the defenders' army, the attackers win by holding the plaza: a unit of at least %d men in it, and no defending unit within %d m beyond it, for %d seconds in a row (the ring round the plaza fills) - then every defender breaks. Where there is a citadel (acropolis or Byrsa) its court is the place to hold, so the attackers must break two gates; its gate starts open and the defenders shut it when they fall back into it." % [
			BattleSim.CAPTURE_MEN, BattleSim.CAPTURE_CLEAR / 1024, BattleSim.CAPTURE_TICKS / 10],
		"",
		"The enemy. Attacking, the AI picks the weakest, nearest gate, brings its engines up to shoot it from out of bow range, covers it with its archers, sends heavy foot to hack at it when it has no engines (or they take too long; never at an iron-bound gate), gives the ram to a unit it can spare and its ladders to its heaviest foot, and storms in once a gate is down, making for the plaza; its cavalry waits outside until the defenders break. Defending, it shuts the gates when you come near, keeps its archers on the land walls (bringing them down when a gate falls and the enemy is near), holds each gate from inside with its steadiest foot, keeps the rest at the plaza to fall on whatever gets in, and when the town is lost pulls back into its citadel and shuts it. Attacking a citadel, the AI brings the ram up to its gate (or hacks at a level 1 gate with its heaviest foot) and shoots it with any engine in reach; with nothing that can hurt the gate it waits out of bow shot.",
		"",
		"Deployment. A battle may open with a deployment phase (the campaign's Deployment time setting, or a custom battle's): nothing moves or shoots and the clock stands still while you place your units inside your zone (blue; the enemy's is outlined red). Tap, drag a line or move a group as usual: the men stand there at once. A point outside the zone is kept to its edge on the field; defending a town you place inside the walls (open ground of the town) or straight onto a walkway (foot and missile troops). The AI's line is placed at the start so you can see it. Start battle (or Enter) when ready; with two players the battle starts when both are ready, or when the time runs out.",
	]
	return "\n".join(lines)


func open(ty: int = -1) -> void:
	visible = true
	show_type(current if ty < 0 else ty)


func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


func show_type(ty: int) -> void:
	current = clampi(ty, 0, UT.count() + 1)
	for k in _list.size():
		_list[k].set_pressed_no_signal(k == current)
	var terr := current >= UT.count()
	terrain_page.visible = terr
	entry.visible = not terr
	if terr:
		terrain_text.text = terrain_help() if current == UT.count() else siege_help()
		terrain_page.scroll_vertical = 0
	else:
		entry.set_unit_type(current, side_color)


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_ESCAPE:
				close()
			KEY_LEFT, KEY_UP:
				show_type((current + _pages() - 1) % _pages())
			KEY_RIGHT, KEY_DOWN:
				show_type((current + 1) % _pages())
		get_viewport().set_input_as_handled()


func _button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(96, 54)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 17)
	return b
