extends CanvasLayer
## On-device diagnosis panel (2026-11-09; `?diag=1` on the web, `--diag` on the desktop; docs/design/ui.md). Over the battle:
## the view, the 3D path, the quality tier, the last soldier probe's drawn count, the WebGL context's parameters and the
## client_log lines tools/web_diag.js captured (E console.error, W GL-related warnings, X page errors, R rejections, S failed
## shader compiles / links), and a "Send log" button that posts a client_log event at once. Off otherwise. View only: it reads the
## battle and the page, writes no sim state and nothing the hash covers; the tests' default runs never build it.

const Quality := preload("res://game/quality.gd")
const BoardView := preload("res://game/board_view.gd")
const SoldierLayer := preload("res://game/soldier_layer.gd")

var battle = null
var _info: Label
var _log: Label
var _status: Label
var _scroll: ScrollContainer
var _t := 0.0
var _panel: PanelContainer
var _collapsed := false
var _deep_str := ""


## True with `--diag` / `?diag=1` (the web query reads as a launch arg).
static func wanted() -> bool:
	for a in SoldierLayer._launch_args():
		var s := str(a)
		if s == "--diag" or s == "--diag=1" or s == "--diag=true":
			return true
	return false


func _ready() -> void:
	layer = 90
	_panel = PanelContainer.new()
	_panel.position = Vector2(4, 4)
	_panel.custom_minimum_size = Vector2(430, 0)
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.02, 0.03, 0.02, 0.86)
	sb.set_content_margin_all(5)
	_panel.add_theme_stylebox_override("panel", sb)
	add_child(_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 3)
	_panel.add_child(v)
	var row := HBoxContainer.new()
	v.add_child(row)
	var send := Button.new()
	send.text = "Send log"
	send.custom_minimum_size = Vector2(96, 34)
	send.pressed.connect(_on_send)
	row.add_child(send)
	var tex_b := Button.new()
	tex_b.text = "Tex"
	tex_b.custom_minimum_size = Vector2(56, 34)
	tex_b.pressed.connect(_on_tex)
	row.add_child(tex_b)
	var hide_b := Button.new()
	hide_b.text = "Hide"
	hide_b.custom_minimum_size = Vector2(64, 34)
	hide_b.pressed.connect(_on_hide)
	row.add_child(hide_b)
	_status = _mk_label(11)
	_status.text = " diag"
	row.add_child(_status)
	_info = _mk_label(10)
	v.add_child(_info)
	_scroll = ScrollContainer.new()
	_scroll.custom_minimum_size = Vector2(420, 170)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(_scroll)
	_log = _mk_label(9)
	_log.custom_minimum_size = Vector2(410, 0)
	_log.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	_scroll.add_child(_log)
	_refresh()


func _mk_label(sz: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", sz)
	l.add_theme_color_override("font_color", Color(0.85, 1.0, 0.8))
	l.mouse_filter = Control.MOUSE_FILTER_PASS
	return l


func _process(delta: float) -> void:
	_t += delta
	if _t >= 1.0:
		_t = 0.0
		_refresh()


func _on_tex() -> void:
	var d: Dictionary = {}
	var tele = get_node_or_null("/root/Telemetry")
	if tele != null:
		d = tele.diag_snapshot(true)
	_deep_str = tex_text(battle.view3d if battle != null else null, _gl_max(d), true)
	_refresh()


static func _gl_max(d: Dictionary) -> int:
	var gl = d.get("gl", {})
	return int((gl as Dictionary).get("MAX_TEXTURE_SIZE", 0)) if gl is Dictionary else 0


func _on_hide() -> void:
	_collapsed = not _collapsed
	_scroll.visible = not _collapsed
	_info.visible = not _collapsed


func _on_send() -> void:
	var tele = get_node_or_null("/root/Telemetry")
	if tele == null or not tele.enabled:
		_status.text = " telemetry off"
		return
	if not OS.has_feature("web"):
		tele.event("client_log", {"reason": "button", "log": {"desktop": 1}})
		tele.flush()
		_status.text = " sent (desktop, no capture)"
		return
	tele.client_log("button", true)
	tele.flush()
	_status.text = " sent at %ds" % int(Time.get_ticks_msec() / 1000.0)


## The overlay's text lines, also read by tests.
func info_text(d: Dictionary) -> String:
	var path := ""
	var v3 = battle.view3d if battle != null else null
	if v3 != null and v3.has_method("path_name"):
		path = v3.path_name()
	var view := "3d" if BoardView.v3d else ("oblique" if BoardView.oblique else "top")
	var probe: Dictionary = battle.probe_last if battle != null else {}
	var s := "view %s  3D path %s  quality %s (pref %s)  fps %d\n" % [view, path if path != "" else "-", "low" if Quality.is_low() else "high", Quality.load_pref(), Engine.get_frames_per_second()]
	s += "probe: " + (("drawn %d of %d men, path %s, tick %d" % [int(probe.get("drawn", 0)), int(probe.get("men", 0)), str(probe.get("path", "")), int(probe.get("tick", 0))]) if not probe.is_empty() else "none yet") + "\n"
	s += "GPU %s | %s | %s\n" % [RenderingServer.get_video_adapter_name(), RenderingServer.get_video_adapter_api_version(), str(get_viewport().get_visible_rect().size)]
	var gl = d.get("gl", {})
	if gl is Dictionary and not (gl as Dictionary).is_empty():
		var keys := ["MAX_TEXTURE_SIZE", "MAX_VERTEX_TEXTURE_IMAGE_UNITS", "MAX_TEXTURE_IMAGE_UNITS", "MAX_VARYING_VECTORS", "MAX_FRAGMENT_UNIFORM_VECTORS", "MAX_VERTEX_UNIFORM_VECTORS", "MAX_RENDERBUFFER_SIZE", "DEPTH_BITS", "STENCIL_BITS", "SAMPLES", "ext_n", "EXT_color_buffer_float", "OES_texture_float_linear", "EXT_texture_filter_anisotropic", "attr_stencil"]
		var parts: Array = []
		for k in keys:
			if (gl as Dictionary).has(k):
				parts.append("%s=%s" % [str(k).replace("MAX_", "").replace("_IMAGE_UNITS", "_IU").replace("_VECTORS", "_V"), str(gl[k])])
		s += "GL " + " ".join(parts) + "\n"
		s += "GL renderer: %s" % str(gl.get("UNMASKED_RENDERER", gl.get("RENDERER", "?")))
	elif OS.has_feature("web"):
		s += "GL: no context captured (is diag.js loaded?)"
	else:
		s += "GL: desktop (no page capture)"
	return s


## One line per texture the men's material samples: class, pixel size as the engine holds it (against the context's
## MAX_TEXTURE_SIZE: a larger sheet is an incomplete texture and samples black), and for an ImageTexture its Image format. The
## "Tex" button adds the heavy facts (a readback of each image: format, mipmaps).
static func tex_text(v3, mx: int, deep := false) -> String:
	if v3 == null or v3.men_mat == null:
		return "(no 3D men material)"
	var out := "textures (GL MAX_TEXTURE_SIZE %s):\n" % (str(mx) if mx > 0 else "?")
	for n in ["ob_shade", "ob_mask", "ob_tab", "atlas_shade", "atlas_mask", "proc_tex", "pal_tex"]:
		var t = v3.men_mat.get_shader_parameter(n)
		if not (t is Texture2D):
			out += "  %s: none\n" % n
			continue
		var tex := t as Texture2D
		var big := " TOO BIG" if mx > 0 and maxi(tex.get_width(), tex.get_height()) > mx else ""
		var fmt := ""
		if tex is ImageTexture:
			fmt = " fmt %d" % (tex as ImageTexture).get_format()
		out += "  %s: %s %dx%d%s%s" % [n, tex.get_class(), tex.get_width(), tex.get_height(), fmt, big]
		if deep:
			var im := tex.get_image()
			out += (" image fmt %d mips %s" % [im.get_format(), str(im.has_mipmaps())]) if im != null else " (no image)"
		out += "\n"
	return out


func log_text(d: Dictionary) -> String:
	var lines = d.get("lines", [])
	if not (lines is Array) or (lines as Array).is_empty():
		return "(no captured lines)"
	var out := ""
	for l in lines:
		out += "%s %5.1fs%s %s\n" % [str(l.get("l", "?")), float(l.get("t", 0)) / 1000.0, (" x%d" % int(l["n"])) if int(l.get("n", 1)) > 1 else "", str(l.get("m", ""))]
	return out


func _refresh() -> void:
	var tele = get_node_or_null("/root/Telemetry")
	var d: Dictionary = tele.diag_snapshot(true) if tele != null else {}
	_info.text = info_text(d)
	_log.text = (_deep_str if _deep_str != "" else tex_text(battle.view3d if battle != null else null, _gl_max(d))) + log_text(d)
