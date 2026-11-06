extends CanvasLayer
## The battle's loading plate (docs/design/ui.md "The battle's loading bar"): over the battle screen from the Start tap (the
## sandbox, a custom battle, a campaign battle) until the first playable frame. The wood of the table covers whatever the
## setup has built so far (nothing shows or takes a tap until the last step); on it a plate in the table's chrome (the rule
## box) with the battle's name, a brass progress bar and the phase in hand ("Painting the board" ...). The plate fades in only
## after SHOW_SEC, so a battle that loads at once never flashes it. View only: the battle (game/battle.gd _load_run) calls
## set_phase() before each step and finish() when the first frame is drawn.

const Kit := preload("res://game/campaign/ui_kit.gd")
const LoadingPanel := preload("res://game/campaign/loading_panel.gd")

const SHOW_SEC := 0.4      # a load shorter than this never shows the plate
const FADE_IN_SEC := 0.25
const FADE_OUT_SEC := 0.18

var plate: PanelContainer
var title_label: Label
var phase_label: Label
var bar: ProgressBar
var cover: Control
var _t := 0.0
var _title := ""
var _pack := "rome"
var _fading := false
var _fade_t := 0.0
var shown_for_test := false   # tests and shots: the plate at full alpha at once


func setup(p_title: String, p_pack: String) -> void:
	_title = p_title
	_pack = p_pack
	layer = 110   # (under the oblique pack's download bar, layer 120, which keeps its Cancel button)
	name = "battle_loading"
	cover = Control.new()
	cover.name = "loading_cover"
	cover.set_anchors_preset(Control.PRESET_FULL_RECT)
	cover.mouse_filter = Control.MOUSE_FILTER_STOP   # nothing reaches the battle below
	add_child(cover)
	var wood := TextureRect.new()
	wood.set_anchors_preset(Control.PRESET_FULL_RECT)
	wood.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wood.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	wood.stretch_mode = TextureRect.STRETCH_SCALE
	wood.texture = LoadingPanel.keyart(_pack)
	cover.add_child(wood)
	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cover.add_child(centre)
	plate = Kit.panel(Color(0.1, 0.075, 0.05, 0.95), 16)
	plate.name = "loading_plate"
	plate.custom_minimum_size = Vector2(minf(360.0, get_viewport().get_visible_rect().size.x - 32.0), 0)
	plate.modulate.a = 0.0
	centre.add_child(plate)
	var v := Kit.vbox(8)
	plate.add_child(v)
	title_label = Kit.title(_title, 22)
	title_label.name = "loading_title"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(title_label)
	v.add_child(Kit.rule())
	bar = ProgressBar.new()
	bar.name = "loading_bar"
	bar.min_value = 0.0
	bar.max_value = 1.0
	bar.value = 0.0
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(240, 14)
	bar.add_theme_stylebox_override("background", Kit.rule_box(Color(0, 0, 0, 0.35), 0.0, 3, Color(Kit.COL_RULE, 0.45)))
	bar.add_theme_stylebox_override("fill", Kit.box(Color(Kit.COL_RULE, 0.95), 0.0, 3))
	v.add_child(bar)
	phase_label = Kit.label("", Kit.FONT, Kit.COL_BONE)
	phase_label.name = "loading_phase"
	phase_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	phase_label.custom_minimum_size.y = 22.0
	v.add_child(phase_label)


## The phase about to run and the bar's fraction (0-1) of the setup done before it.
func set_phase(text: String, frac: float) -> void:
	if bar == null:
		return
	bar.value = clampf(frac, 0.0, 1.0)
	phase_label.text = text + "..." if text != "" else ""


## The first frame is drawn: lift the plate (a short fade when it was showing) and free the layer.
func finish() -> void:
	_fading = true
	_fade_t = 0.0
	cover.mouse_filter = Control.MOUSE_FILTER_IGNORE   # (taps reach the battle as it fades)
	if plate != null and plate.modulate.a <= 0.0:
		queue_free()   # (never shown: nothing to fade)


func _process(delta: float) -> void:
	if plate == null:
		return
	if _fading:
		_fade_t += delta
		var k := clampf(_fade_t / FADE_OUT_SEC, 0.0, 1.0)
		cover.modulate.a = 1.0 - k
		if k >= 1.0:
			queue_free()
		return
	_t += delta
	plate.modulate.a = 1.0 if shown_for_test else clampf((_t - SHOW_SEC) / FADE_IN_SEC, 0.0, 1.0)
