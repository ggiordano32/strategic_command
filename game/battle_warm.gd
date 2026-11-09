extends RefCounted
## Warming the battle's once-per-session caches while the menu idles (docs/design/ui.md "The battle's loading bar"). The first
## battle of a session built these on its Start tap (desktop ms; the web runs several times that, a phone more): the soldiers'
## procedural atlas 270, the tree atlas 145, the oblique figure sheets (SpriteOb) 690, the kit sheet (KitOb) 210, the 3D kit
## meshes (Kit3D) 160. They are static caches (every battle after the first found them built), so building them one a second
## from a few seconds after the menu appears moves about 1.5 s of desktop time off the first Start. Only what the Battle view
## in use needs; (the web has them in index.pck since 2026-11-09; before: only once the oblique pack was mounted, never before: a cache built without the sheets would
## latch empty); never in a headless run, never while a battle is open or starting. View only.

const SoldierLayer := preload("res://game/soldier_layer.gd")
const TreeLayer := preload("res://game/tree_layer.gd")
const SpriteOb := preload("res://game/sprite_ob.gd")
const KitOb := preload("res://game/kit_ob.gd")
const Kit3D := preload("res://game/kit3d.gd")
const BoardView := preload("res://game/board_view.gd")

const FIRST_SEC := 4.0     # the menu has been up this long before the first one
const GAP_SEC := 1.2       # between two

## Steps run so far (a test reads it).
static var done: Array[String] = []
static var _started := false
static var _gap := GAP_SEC


## `busy` returns true while a battle is open or starting (the warm-up then stops for good).
static func start(host: Node, busy: Callable) -> void:
	if _started or DisplayServer.get_name() == "headless" or "--no-warm" in OS.get_cmdline_user_args():
		return   # (--no-warm, and on the web "?no-warm=1": a cold first Start, for measuring)
	if OS.has_feature("web") and _web_has("no-warm"):
		return
	_started = true
	var first := FIRST_SEC
	if "--warm-now" in OS.get_cmdline_user_args() or (OS.has_feature("web") and _web_has("warm-now")):
		first = 0.1   # (a testing aid: the whole warm-up at once, for measuring a first Start that found it done)
		_gap = 0.05
	_later(host, busy, 0, 0, first)


static func _web_has(key: String) -> bool:
	var q = JavaScriptBridge.eval("window.location.search", true)
	return q is String and (q as String).contains(key)


## Every step at once (tests/load_timing.gd --warm).
static func _run_all() -> void:
	var view := BoardView.pref()
	SoldierLayer._make_atlas()
	TreeLayer._atlas()
	if view != "top":
		SpriteOb.ensure()
		KitOb.ok()
	if view == "3d":
		Kit3D.ok()


static func _later(host: Node, busy: Callable, step: int, tries: int, sec: float) -> void:
	if not is_instance_valid(host) or not host.is_inside_tree():
		return
	var ref: WeakRef = weakref(host)   # (the menu may be gone by then: a test frees it)
	host.get_tree().create_timer(sec).timeout.connect(func():
		var h: Node = ref.get_ref() as Node
		if h != null:
			_run(h, busy, step, tries))


static func _run(host: Node, busy: Callable, step: int, _tries: int) -> void:
	if busy.call():
		return
	var view := BoardView.pref()
	var sheets := view != "top"
	match step:
		0:
			SoldierLayer._make_atlas()
			done.append("soldier_atlas")
		1:
			TreeLayer._atlas()
			done.append("tree_atlas")
		2:
			if sheets:
				SpriteOb.ensure()
				done.append("sprite_ob")
		3:
			if sheets:
				KitOb.ok()
				done.append("kit_ob")
		4:
			if view == "3d":
				Kit3D.ok()
				done.append("kit3d")
		_:
			return
	_later(host, busy, step + 1, 0, _gap)
