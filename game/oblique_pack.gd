extends Node
## The oblique sheets' on-demand pack for the web (docs/design/art_pipeline.md "The real sheets", "The on-demand pack").
## The web export leaves assets/sprites_ob and assets/battlekit_ob out of index.pck (12 MB); tools/export_web.sh writes
## them as build/web/oblique.pck. When the Battle view is Oblique on the web and the sheets are absent, `ensure` fetches
## that file from the page's own origin (an HTTPRequest, written to user://), mounts it with ProjectSettings.load_resource_pack,
## and tells the loaders (SpriteOb, KitOb) to look again; the next battle then finds the real sheets. A small bar on
## its own canvas layer shows the progress with a Cancel button. Oblique is the default view (2026-10-30), so a first-time
## player meets this at the start screen (the boot's `ensure`) or at the first battle (the battle waits for it). A
## battle whose sheets are not mounted is drawn from the top (BoardView.web_top). Cancel: that battle from the top; the
## next battle's start asks once more (never the boot or the menu by itself: no prompt loop). A failure: one notice
## for the session ("the battles use the top view"), no automatic retry; picking Oblique in Options tries again
## (`should_start`). Once mounted the pack stays for the session. Native builds never fetch (the files are in the
## main pack). View only: nothing here touches the sim.

const SpriteOb := preload("res://game/sprite_ob.gd")
const KitOb := preload("res://game/kit_ob.gd")
const Kit3D := preload("res://game/kit3d.gd")
const BoardView := preload("res://game/board_view.gd")

enum State { ABSENT, DOWNLOADING, LOADED, FAILED, CANCELLED }

signal state_changed(new_state: int)
signal progress(done: int, total: int)
## Emitted once per attempt when it ends: true when the sheets are mounted.
signal finished(ok: bool)

const PACK_NAME := "oblique.pck"
const SIZE_NOTE := "12 MB"
const PROBE_FILES: Array[String] = ["res://assets/sprites_ob/manifest.json", "res://assets/battlekit_ob/manifest.json"]
const LOCAL := "user://oblique.pck"

static var inst: Node = null
static var told_failed := false     # the failure notice is shown once a session

var state: int = State.ABSENT
var url := ""
var done_bytes := 0
var total_bytes := 0
## Test seams: a Callable returning a request node (HTTPRequest or a stub with the same surface), a Callable(path)
## -> bool mounting a pack, and a Callable() -> bool saying whether the sheets are present.
var make_request: Callable = func() -> Node: return HTTPRequest.new()
var mount: Callable = func(path: String) -> bool: return ProjectSettings.load_resource_pack(path)
var present: Callable = sheets_present
var write: Callable = func(path: String, data: PackedByteArray) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null or data.is_empty():
		return false
	f.store_buffer(data)
	f.close()
	return true
var _req: Node = null
var _bar: CanvasLayer = null
var _label: Label = null
var _cancel: Button = null
var _fill: ColorRect = null
var _ui := true


static func sheets_present() -> bool:
	for f in PROBE_FILES:
		if not FileAccess.file_exists(f):
			return false
	return true


## True on the web when the Battle view is Oblique (or 3D, which draws the same sheets) and the sheets are not mounted.
static func wanted() -> bool:
	return OS.has_feature("web") and (BoardView.pref() == "oblique" or BoardView.pref() == "3d") and not sheets_present()


## The page's directory plus the pack, versioned by the stamp's "ob:" token (the sheets' content hash) so a new build
## refetches only when the sheets changed (the server answers every file "no-cache" with an ETag: a cheap 304 otherwise).
static func pack_url(base: String, stamp: String) -> String:
	var b := base.get_slice("#", 0).get_slice("?", 0)
	b = b.substr(0, b.rfind("/") + 1)
	var v := ""
	for part in stamp.split(" ", false):
		if part.begins_with("ob:"):
			v = part.substr(3)
	if v == "":
		v = stamp.strip_edges().get_slice(" ", 0)
	return b + PACK_NAME + (("?v=" + v) if v != "" else "")


## Whether an `ensure` starts a fetch after the last attempt ended in `st`: always for the player's own Oblique pick
## (`user`); never while one runs or once loaded; after a cancel only at a battle's start (`battle`: that battle was
## drawn from the top, the next one asks once more); after a failure only for the player's pick (said once).
static func should_start(st: int, user: bool, battle: bool) -> bool:
	if st == State.DOWNLOADING or st == State.LOADED:
		return false
	if user or st == State.ABSENT:
		return true
	if st == State.CANCELLED:
		return battle
	return false


## The shared instance (on the root, so it outlives scene changes), started when `wanted()` (and `should_start`).
## Returns it while a download runs (to `wait()` on), else null. `user`: the player picked Oblique in Options;
## `battle`: a battle is starting.
static func ensure(user := false, battle := false) -> Node:
	if inst != null and is_instance_valid(inst):
		if wanted() and should_start(inst.state, user, battle):
			inst.start()
		return inst if (inst.state == State.DOWNLOADING) else null
	if not wanted():
		return null
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	inst = (load("res://game/oblique_pack.gd") as GDScript).new()
	inst.name = "ObliquePack"
	tree.root.add_child(inst)
	inst.start()
	return inst if inst.state == State.DOWNLOADING else null


func _set_state(s: int) -> void:
	state = s
	state_changed.emit(s)


func start() -> void:
	if state == State.DOWNLOADING:
		return
	if present.call():
		_set_state(State.LOADED)
		return
	var base := "http://localhost/"
	if OS.has_feature("web"):
		var b = JavaScriptBridge.eval("document.baseURI", true)
		if b is String:
			base = b
	var stamp := ""
	if FileAccess.file_exists("res://build_stamp.txt"):
		stamp = FileAccess.get_file_as_string("res://build_stamp.txt").strip_edges()
	url = pack_url(base, stamp)
	_begin(url)


## Starts the fetch of `u` (tests call this with the stubs set).
func _begin(u: String) -> void:
	url = u
	done_bytes = 0
	total_bytes = 0
	_req = make_request.call()
	add_child(_req)
	_req.request_completed.connect(_on_completed)
	var err: int = _req.request(url)
	if err != OK:
		print("oblique pack: cannot start the fetch of ", url, " (error ", err, ")")
		_end(State.FAILED)
		return
	print("oblique pack: downloading ", url)
	_set_state(State.DOWNLOADING)
	set_process(true)
	_show_bar()


func _ready() -> void:
	set_process(false)


func _process(_dt: float) -> void:
	if state != State.DOWNLOADING or _req == null:
		return
	poll()


## Reads the request's counters (every frame while downloading).
func poll() -> void:
	var d: int = _req.get_downloaded_bytes()
	var t: int = _req.get_body_size()
	if d != done_bytes or t != total_bytes:
		done_bytes = d
		total_bytes = t
		progress.emit(d, t)
		_update_bar()


func cancel() -> void:
	if state != State.DOWNLOADING:
		return
	_req.cancel_request()
	print("oblique pack: cancelled")
	_end(State.CANCELLED)


func _on_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if state != State.DOWNLOADING:
		return
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		print("oblique pack: fetch failed (result ", result, ", HTTP ", code, "): the top view stays")
		_end(State.FAILED)
		return
	# The body in memory (the web's HTTPRequest does not write download_file), then the file the pack is mounted from.
	if not write.call(LOCAL, body):
		print("oblique pack: cannot write ", LOCAL, " (", body.size(), " bytes): the top view stays")
		_end(State.FAILED)
		return
	if not mount.call(LOCAL):
		print("oblique pack: the pack would not mount (", body.size(), " bytes): the top view stays")
		_end(State.FAILED)
		return
	done_bytes = body.size()
	# The loaders decide once per session; make them decide again.
	SpriteOb.reset()
	KitOb.reset()
	Kit3D.reset()
	var ok: bool = present.call()
	if ok:
		print("oblique pack: loaded (", done_bytes, " bytes), the oblique sheets found")
	else:
		print("oblique pack: mounted but the oblique sheets are not in it: the top view stays")
	_end(State.LOADED if ok else State.FAILED)


func _end(s: int) -> void:
	set_process(false)
	if _req != null:
		_req.queue_free()
		_req = null
	_hide_bar()
	_set_state(s)
	if s == State.FAILED and not told_failed:
		told_failed = true
		_notice("Could not download the oblique figures: battles use the top view. Pick Oblique in Options to try again.")
	finished.emit(s == State.LOADED)


## A one-line notice on the bar's layer for a few seconds (the failure, once a session).
func _notice(text: String) -> void:
	print("oblique pack: ", text)
	if not _ui:
		return
	var cl := CanvasLayer.new()
	cl.layer = 120
	add_child(cl)
	var pc := PanelContainer.new()
	pc.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 16)
	cl.add_child(pc)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.10, 0.12, 0.10, 0.94)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(10)
	pc.add_theme_stylebox_override("panel", sb)
	var l := Label.new()
	l.text = text
	pc.add_child(l)
	get_tree().create_timer(6.0).timeout.connect(cl.queue_free)


## Waits for the running attempt (the battle's start calls this so it never draws the top view for a download that is
## nearly done): returns when the attempt ends, at once when none runs.
func wait() -> void:
	if state == State.DOWNLOADING:
		await finished


# --- the progress bar ---------------------------------------------------------------------------------------------

func _show_bar() -> void:
	if not _ui or _bar != null:
		return
	_bar = CanvasLayer.new()
	_bar.layer = 120
	add_child(_bar)
	var pc := PanelContainer.new()
	pc.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 16)
	_bar.add_child(pc)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.10, 0.12, 0.10, 0.94)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(10)
	pc.add_theme_stylebox_override("panel", sb)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	pc.add_child(hb)
	var vb := VBoxContainer.new()
	hb.add_child(vb)
	_label = Label.new()
	vb.add_child(_label)
	var track := ColorRect.new()
	track.color = Color(1, 1, 1, 0.15)
	track.custom_minimum_size = Vector2(260, 6)
	vb.add_child(track)
	_fill = ColorRect.new()
	_fill.color = Color(0.85, 0.75, 0.40)
	_fill.size = Vector2(0, 6)
	track.add_child(_fill)
	_cancel = Button.new()
	_cancel.text = "Cancel"
	_cancel.name = "oblique_pack_cancel"
	_cancel.pressed.connect(cancel)
	hb.add_child(_cancel)
	_update_bar()


func _update_bar() -> void:
	if _label == null:
		return
	var pct := ""
	var frac := 0.0
	if total_bytes > 0:
		frac = clampf(float(done_bytes) / float(total_bytes), 0.0, 1.0)
		pct = "  %d%%" % int(frac * 100.0)
	_label.text = "Downloading the oblique sheets, %s%s" % [SIZE_NOTE, pct]
	_fill.size = Vector2(260.0 * frac, 6.0)


func _hide_bar() -> void:
	if _bar != null:
		_bar.queue_free()
		_bar = null
		_label = null
		_fill = null
		_cancel = null
