extends RefCounted
## The sea battle's Key: what each line and marker on the water means. ONE list (KINDS) names every kind the battle
## draws and one function (col) gives its colour, used by the drawing code (game/sea_battle.gd) and by the Key panel,
## so they cannot disagree; tests/sea_help_test.gd checks the panel lists every kind and the drawing uses only these.
## One colour per meaning:
##   the selected ship, her course and destination: her flag's colour (lightened)   attack order: red
##   boarding (the ship to board, the grapple ring): gold                            fire ship (target, lighting reach): orange
##   flee heading: violet                    broadside arcs and range: teal           wind (arrow, rose): white
##   wake: white foam                        grapple lines: dark brown
## View only. The panel is the open / closed state in settings.cfg [ui] sea_key.

const Kit := preload("res://game/campaign/ui_kit.gd")
const SETTINGS := "user://settings.cfg"

## [id, name, one line, sample style]; styles: ring, dash, dashring, line, wedge, arrow, foam, ringdash
const KINDS: Array = [
	["selected", "Selected ship", "A ring in her flag's colour. Her course is drawn in the same colour.", "ring"],
	["course", "Course", "Dashed, in her flag's colour: the path she will sail, tacking if the wind is against her.", "dash"],
	["waypoint", "Destination", "A ring where her course ends.", "ring"],
	["attack", "Attack order", "Red: the enemy she is sent to engage.", "dashring"],
	["board", "Boarding", "Gold: the ship she will board, and the pulsing ring round two ships locked together.", "dashring"],
	["fire", "Fire ship", "Orange: the ship the fire ship is sent at. The faint ring is how close she must be to light.", "dashring"],
	["flee", "Flee", "Violet: the heading she runs on for the map edge.", "dash"],
	["arcs", "Guns", "Teal wedges: the selected ship's broadside arcs and range, brighter on a side that is loaded.", "wedge"],
	["wind", "Wind", "White arrow in the top-left rose: the way the wind blows.", "arrow"],
	["wake", "Wake", "White foam behind a moving ship.", "foam"],
	["grapple", "Grapples", "Dark lines between ships fighting hand to hand.", "line"],
]

static var hinted := false   # the 3 s pointer at the Key is shown once per session


static func ids() -> Array:
	var out: Array = []
	for k in KINDS:
		out.append(k[0])
	return out


## The colour of a kind. flag: the player's flag colour (selected, course, destination).
static func col(id: String, flag: Color = Color(0.25, 0.55, 0.95), a: float = 1.0) -> Color:
	var c := Color.WHITE
	match id:
		"selected", "course", "waypoint":
			c = flag.lightened(0.35)
		"attack":
			c = Color(1.0, 0.3, 0.27)
		"board":
			c = Color(1.0, 0.8, 0.25)
		"fire":
			c = Color(1.0, 0.55, 0.15)
		"flee":
			c = Color(0.75, 0.6, 1.0)
		"arcs":
			c = Color(0.35, 0.9, 0.85)
		"wind":
			c = Color(1, 1, 1)
		"wake":
			c = Color(0.95, 0.98, 1.0)
		"grapple":
			c = Color(0.15, 0.1, 0.06)
	return Color(c, a)


static func load_pref() -> bool:
	var cf := ConfigFile.new()
	return cf.load(SETTINGS) == OK and int(cf.get_value("ui", "sea_key", 0)) != 0


static func save_pref(on: bool) -> void:
	var cf := ConfigFile.new()
	cf.load(SETTINGS)
	cf.set_value("ui", "sea_key", 1 if on else 0)
	cf.save(SETTINGS)


## A drawn sample of a kind on a strip of sea.
class Sample extends Control:
	const KeyS := preload("res://game/sea_key.gd")
	var id := ""
	var style := ""
	var flag := Color(0.25, 0.55, 0.95)

	func _init(p_id: String, p_style: String, p_flag: Color) -> void:
		id = p_id
		style = p_style
		flag = p_flag
		custom_minimum_size = Vector2(76, 30)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := KeyS.col(id, flag)
		var sz := size
		draw_rect(Rect2(Vector2.ZERO, sz), Color(0.13, 0.36, 0.5))
		var m := sz.y * 0.5
		match style:
			"ring":
				draw_arc(Vector2(sz.x * 0.5, m), 9.0, 0, TAU, 20, c, 2.0, true)
			"dash":
				var x := 6.0
				while x < sz.x - 10.0:
					draw_line(Vector2(x, m), Vector2(minf(x + 8.0, sz.x - 6.0), m), c, 2.0)
					x += 14.0
			"dashring":
				draw_arc(Vector2(sz.x - 14.0, m), 9.0, 0, TAU, 20, c, 2.0, true)
				var x2 := 5.0
				while x2 < sz.x - 26.0:
					draw_line(Vector2(x2, m), Vector2(minf(x2 + 6.0, sz.x - 26.0), m), c, 2.0)
					x2 += 11.0
			"line":
				for k in 4:
					draw_line(Vector2(8, m - 6 + k * 4), Vector2(sz.x - 8, m + 6 - k * 3), c, 1.6)
			"wedge":
				var o := Vector2(10, m)
				draw_arc(o, 52.0, -0.5, 0.5, 10, c, 1.6)
				draw_line(o, o + Vector2(cos(-0.5), sin(-0.5)) * 52.0, c, 1.2)
				draw_line(o, o + Vector2(cos(0.5), sin(0.5)) * 52.0, c, 1.2)
			"arrow":
				draw_line(Vector2(10, m), Vector2(sz.x - 16, m), c, 3.0, true)
				draw_colored_polygon(PackedVector2Array([Vector2(sz.x - 8, m), Vector2(sz.x - 20, m - 6), Vector2(sz.x - 20, m + 6)]), c)
			"foam":
				for k in 5:
					draw_circle(Vector2(sz.x - 12 - k * 13, m + sin(k * 1.7) * 3.0), 4.5 - k * 0.7, Color(c, 0.9 - k * 0.15))


## The Key panel (a trim panel with a close button); build() once, show / hide with set_open().
class KeyPanel extends PanelContainer:
	const KeyS := preload("res://game/sea_key.gd")
	signal toggled(open: bool)

	func _init(flag: Color) -> void:
		name = "sea_key_panel"
		add_theme_stylebox_override("panel", KeyS.Kit.trim_box(Color(KeyS.Kit.PANEL_BG, 0.96), 12.0))
		var v := KeyS.Kit.vbox(5)
		add_child(v)
		var head := KeyS.Kit.hbox(8)
		var t := KeyS.Kit.title("Key", 20)
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(t)
		var x := KeyS.Kit.button("Close", func(): toggled.emit(false), 70, KeyS.Kit.FONT_SMALL)
		x.name = "sea_key_close"
		head.add_child(x)
		v.add_child(head)
		v.add_child(KeyS.Kit.rule())
		var sc := KeyS.Kit.TouchScroll.new()
		sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		sc.custom_minimum_size = Vector2(0, 120)
		sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
		v.add_child(sc)
		var list := KeyS.Kit.vbox(5)
		list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sc.add_child(list)
		for k in KeyS.KINDS:
			var row := KeyS.Kit.hbox(8)
			row.name = "sea_key_row_" + str(k[0])
			row.add_child(Sample.new(str(k[0]), str(k[3]), flag))
			var tv := KeyS.Kit.vbox(0)
			tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			tv.add_child(KeyS.Kit.label(str(k[1]), KeyS.Kit.FONT_SMALL + 1, KeyS.Kit.COL_GOLD))
			tv.add_child(KeyS.Kit.label(str(k[2]), KeyS.Kit.FONT_SMALL, KeyS.Kit.COL_BONE, true))
			row.add_child(tv)
			list.add_child(row)
