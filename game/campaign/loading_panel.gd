extends CanvasLayer
## The "Preparing the campaign" panel (Kit style): a modal dimmed layer with a
## title, a progress bar and the step in hand. Opened at once on the tap that
## starts a new campaign, loads a save, joins an online campaign or enters a
## battle, then each step is announced before its work starts and a frame is
## left in between, so the bar moves and the tap never feels lost:
##
##   var lp := LoadingPanel.open(get_tree().root, "Preparing the campaign", 5)
##   await lp.step("Creating the campaign")
##   ...work...
##   await lp.step("Building the map")
##   ...work...
##   await lp.done()
##
## Each step's time is kept in `timings` ([[label, ms], ...]) and printed
## ("loading: <label> <ms> ms") for measuring.

const Kit := preload("res://game/campaign/ui_kit.gd")

## The last battle build's time (ms; -1 not measured): the panel for entering
## a battle is shown only when the build was slow (see slow_battle()).
static var last_battle_ms := -1.0
const SLOW_MS := 300.0

var total := 1
var index := 0
var timings: Array = []
var bar: ProgressBar
var step_label: Label
var title_label: Label
var _cur := ""
var _t0 := 0


## Show the panel on `host` (a node in the tree; the panel is its child) with
## n_steps steps.
static func open(host: Node, title: String, n_steps: int) -> Node:
	var lp: Node = (load("res://game/campaign/loading_panel.gd") as GDScript).new()
	lp.total = maxi(n_steps, 1)
	lp.layer = 100
	lp.name = "loading_panel"
	host.add_child(lp)
	lp._build(title)
	return lp


## Whether entering a battle should show the panel: the first time (unknown
## cost) and whenever the last build took more than SLOW_MS.
static func slow_battle() -> bool:
	return last_battle_ms < 0.0 or last_battle_ms > SLOW_MS


func _build(title: String) -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP  # modal: no taps reach the screen below
	add_child(dim)
	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.add_child(centre)
	var panel := Kit.panel(Kit.PANEL_BG, 18)
	panel.custom_minimum_size = Vector2(360, 0)
	panel.name = "loading_box"
	centre.add_child(panel)
	var v := Kit.vbox(10)
	panel.add_child(v)
	title_label = Kit.label(title, Kit.FONT_TITLE, Kit.COL_GOLD)
	title_label.name = "loading_title"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title_label)
	bar = ProgressBar.new()
	bar.name = "loading_bar"
	bar.min_value = 0.0
	bar.max_value = float(total)
	bar.value = 0.0
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(320, 16)
	bar.add_theme_stylebox_override("background", Kit.box(Color(1, 1, 1, 0.12), 0.0, 4))
	bar.add_theme_stylebox_override("fill", Kit.box(Kit.COL_GOLD, 0.0, 4))
	v.add_child(bar)
	step_label = Kit.label("", Kit.FONT, Kit.COL_DIM)
	step_label.name = "loading_step"
	step_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(step_label)


func _note() -> void:
	if _cur != "":
		var ms := (Time.get_ticks_usec() - _t0) / 1000.0
		timings.append([_cur, ms])
		print("loading: %s %.0f ms" % [_cur, ms])


## Announce the next step and let a frame draw it; the caller's work follows.
func step(text: String) -> void:
	_note()
	_cur = text
	step_label.text = text + "..."
	bar.value = float(index)
	index += 1
	await get_tree().process_frame
	_t0 = Time.get_ticks_usec()


## The last step is over: the bar is full; close() follows.
func done() -> void:
	_note()
	_cur = ""
	bar.value = bar.max_value
	step_label.text = ""
	await get_tree().process_frame


func close() -> void:
	queue_free()
