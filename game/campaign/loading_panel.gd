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
## The panel sits over the setting's key art (assets/ui/keyart/<pack>.jpg, cover-fitted and darkened 40 %; a dark
## gradient when the file is missing) with a trim panel holding the title in the display face, a one-line tip and the
## progress bar. Used by the campaign start, the battle build and the turn resolve.
##
## Each step's time is kept in `timings` ([[label, ms], ...]) and printed
## ("loading: <label> <ms> ms") for measuring.

const Kit := preload("res://game/campaign/ui_kit.gd")
const CData := preload("res://campaign/cdata.gd")

## The last battle build's time (ms; -1 not measured): the panel for entering
## a battle is shown only when the build was slow (see slow_battle()).
static var last_battle_ms := -1.0
const SLOW_MS := 300.0
## The last turn resolve's time (ms; -1 not measured): the turn resolves behind this panel when it took more than
## RESOLVE_SLOW_MS (see slow_resolve()), else behind the small "Resolving the turn" dialog.
static var last_resolve_ms := -1.0
const RESOLVE_SLOW_MS := 500.0
const KEYART := "res://assets/ui/keyart/%s.jpg"
const TIPS: Array[String] = [
	"Undo (bottom right) takes back your last order of the turn.",
	"Tap another of your fleets with a fleet selected to join them.",
	"In a siege, Assault storms the walls now; Maintain keeps the ring and waits.",
	"Details on a selection opens every order, list and number.",
	"A fortified army stays put, defends better in the field and has a wider zone of control.",
	"A forced march goes half again as far, but the army cannot attack or lay siege.",
	"A battle you would rather not fight can be auto-resolved from the Battles list.",
	"The map key at the bottom left explains every mark on the map.",
	"Chain shot cripples a ship's sails, round shot hurts the hull: close in to board.",
	"Battles in the list show the odds: your chance and the losses you can expect.",
]
static var _art := {}   # pack -> Texture2D or null

var total := 1
var index := 0
var timings: Array = []
var bar: ProgressBar
var step_label: Label
var title_label: Label
var tip_label: Label
var pack := ""
var _cur := ""
var _t0 := 0


## Show the panel on `host` (a node in the tree; the panel is its child) with
## n_steps steps.
static func open(host: Node, title: String, n_steps: int, p_pack: String = "") -> Node:
	var lp: Node = (load("res://game/campaign/loading_panel.gd") as GDScript).new()
	lp.pack = p_pack
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


## Whether the turn resolve should show this panel: only when the last one was slow.
static func slow_resolve() -> bool:
	return last_resolve_ms > RESOLVE_SLOW_MS


## The key art of a pack, null when its file is missing.
static func keyart(p_pack: String) -> Texture2D:
	if _art.has(p_pack):
		return _art[p_pack]
	var t: Texture2D = null
	var path: String = KEYART % p_pack
	if ResourceLoader.exists(path):
		t = load(path) as Texture2D
	elif FileAccess.file_exists(path):
		var img := Image.load_from_file(path)
		if img != null and not img.is_empty():
			t = ImageTexture.create_from_image(img)
	_art[p_pack] = t
	return t


## A tip for this panel (view only: the global random generator, never the sim's).
static func tip() -> String:
	return TIPS[randi() % TIPS.size()]


func _build(title: String) -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.04, 0.05, 1.0)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP  # modal: no taps reach the screen below
	add_child(dim)
	var art := TextureRect.new()
	art.name = "loading_art"
	art.set_anchors_preset(Control.PRESET_FULL_RECT)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.modulate = Color(0.6, 0.6, 0.6)   # darkened 40 %
	var pk := pack if pack != "" else CData.pack
	art.texture = keyart(pk)
	dim.add_child(art)
	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.add_child(centre)
	var panel := Kit.trim_panel(Color(Kit.PANEL_BG, 0.93), 20)
	panel.custom_minimum_size = Vector2(minf(380.0, get_viewport().get_visible_rect().size.x - 24.0), 0)
	panel.name = "loading_box"
	centre.add_child(panel)
	var v := Kit.vbox(10)
	panel.add_child(v)
	title_label = Kit.title(title, 22)
	title_label.name = "loading_title"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title_label)
	v.add_child(Kit.rule())
	tip_label = Kit.label(tip(), Kit.FONT_SMALL, Kit.COL_BONE, true)
	tip_label.name = "loading_tip"
	tip_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(tip_label)
	bar = ProgressBar.new()
	bar.name = "loading_bar"
	bar.min_value = 0.0
	bar.max_value = float(total)
	bar.value = 0.0
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(280, 16)
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
