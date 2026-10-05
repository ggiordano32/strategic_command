extends RefCounted
## UI scale from the device, not just the stretch: one logical UI pixel is
## K_TOUCH CSS pixels on a touch screen (comfortable touch targets: a 42 px
## button is ~37 CSS px, ~7 mm on a phone) and K_MOUSE CSS pixels with a
## mouse (normal desktop sizes on any monitor), times the player's S / M / L
## choice. The window keeps stretch mode canvas_items, so the battlefield is
## drawn at the window's full resolution; only the logical size changes.
##
## On the web the CSS size comes from window.innerWidth (so it is right
## whatever devicePixelRatio the canvas uses) and touch from
## matchMedia("(pointer: coarse)"); natively from the screen scale and
## DisplayServer. Testing aids: --ui-dpr=X (window pixels per CSS pixel)
## and --ui-touch=0/1 emulate another device.

const K_TOUCH := 0.88
const K_MOUSE := 0.82
const SIZES: Array[float] = [0.85, 1.0, 1.18]
const SIZE_NAMES: Array[String] = ["S", "M", "L"]
const MIN_LOGICAL := Vector2(800, 400)  # never lay the HUD out smaller than this
const SETTINGS := "user://settings.cfg"

static var size_idx := 1
static var _loaded := false
static var _dpr_override := 0.0
static var _touch_override := -1
static var _last := Vector2i.ZERO


static func load_settings() -> void:
	if _loaded:
		return
	_loaded = true
	var cf := ConfigFile.new()
	if cf.load(SETTINGS) == OK:
		size_idx = clampi(int(cf.get_value("ui", "size", 1)), 0, SIZES.size() - 1)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--ui-dpr="):
			_dpr_override = float(a.get_slice("=", 1))
		elif a.begins_with("--ui-touch="):
			_touch_override = int(a.get_slice("=", 1))
		elif a.begins_with("--ui-size="):
			size_idx = clampi(SIZE_NAMES.find(a.get_slice("=", 1).to_upper()), 0, SIZES.size() - 1)


static func save_settings() -> void:
	var cf := ConfigFile.new()
	cf.load(SETTINGS)
	cf.set_value("ui", "size", size_idx)
	cf.save(SETTINGS)


## Window pixels per CSS pixel.
static func window_px_per_css(win: Window) -> float:
	if _dpr_override > 0.0:
		return _dpr_override
	if OS.has_feature("web"):
		var iw = JavaScriptBridge.eval("window.innerWidth", true)
		if (iw is int or iw is float) and float(iw) > 0.0:
			return float(win.size.x) / float(iw)
		return 1.0
	return maxf(DisplayServer.screen_get_scale(), 1.0)


static func is_touch() -> bool:
	if _touch_override >= 0:
		return _touch_override != 0
	if OS.has_feature("web"):
		var c = JavaScriptBridge.eval("window.matchMedia && matchMedia('(pointer: coarse)').matches", true)
		return c == true
	return DisplayServer.is_touchscreen_available() and OS.has_feature("mobile")


## Window pixels per logical UI pixel.
static func scale_for(win: Window) -> float:
	load_settings()
	var k := (K_TOUCH if is_touch() else K_MOUSE) * SIZES[size_idx]
	var s := window_px_per_css(win) * k
	var px := Vector2(win.size)
	# Small windows: shrink rather than overflow the layout.
	s = minf(s, minf(px.x / MIN_LOGICAL.x, px.y / MIN_LOGICAL.y))
	return maxf(s, 0.1)


## Set the window's logical size for the current device and setting.
static func apply(win: Window) -> void:
	var s := scale_for(win)
	var logical := Vector2i(maxi(int(win.size.x / s), 1), maxi(int(win.size.y / s), 1))
	if logical == _last and win.content_scale_size == logical:
		return
	_last = logical
	win.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	win.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	win.content_scale_size = logical


static func cycle_size(win: Window) -> void:
	size_idx = (size_idx + 1) % SIZES.size()
	save_settings()
	apply(win)


static func size_name() -> String:
	return SIZE_NAMES[size_idx]
