extends Node
## Testing aid --prof-tap (also "?prof-tap" in the web build's URL, e.g. "?campaign=rome&prof-tap=5"): the
## overworld's tap latency. Drives real input events through the viewport (a touch on the map, a mouse click on a
## button) for the common selections and bar actions and prints, per action, the median of: "handler" the
## synchronous input handling, "frame" the wall time of the frame that handled it (handler + layout, redraws,
## render submit), "next3" the worst of the 3 frames after, plus the zprof.gd layers of that frame. "base" is the
## median idle frame. Lines start "TAPPROF"; "TAPPROF done" last. tests/tap_latency.gd runs it on a desktop.
## Value: repetitions (default 5); "--prof-tap-ablate" adds direct calls of the screen's refresh pieces.

signal done

const CData := preload("res://campaign/cdata.gd")
const CState := preload("res://campaign/cstate.gd")
const ZProf := preload("res://game/campaign/zprof.gd")
const Geo := preload("res://game/campaign/map_geo.gd")

var cs                      # the campaign screen
var reps := 5
var ablate := false
var frame := 0
var last := 0
var frames: Array = []      # wall ms of each frame since the start
var zp: Array = []          # ZProf.us of each frame
var res := {}               # action -> [[handler, frame, next3, layers], ...]
var order: Array = []       # actions in first-seen order
var queue: Array = []       # [frame to run at, callable]
var cur := ""
var cur_frame := -1
var h_us := 0
var my_army := -1
var start_at := 40


## The aid's value when asked for on the command line or (web) in the page's URL query, else "".
static func wanted() -> String:
	var args := Array(OS.get_cmdline_user_args())
	if OS.has_feature("web"):
		var q = JavaScriptBridge.eval("window.location.search", true)
		if q is String and (q as String).length() > 1:
			for kv in (q as String).substr(1).split("&"):
				args.append("--" + kv)
	var out := ""
	for a in args:
		var s := str(a)
		if s == "--prof-tap":
			out = "5"
		elif s.begins_with("--prof-tap="):
			out = s.get_slice("=", 1)
		elif s == "--prof-tap-ablate":
			out += "+ablate"
	return out


func _init(screen, spec: String) -> void:
	cs = screen
	name = "tap_prof"
	reps = maxi(1, int(spec.get_slice("+", 0))) if spec.get_slice("+", 0) != "" else 5
	ablate = spec.contains("+ablate")
	process_priority = -1000   # (first in the frame: the frame wall times are measured from here)
	ZProf.on = true


func _ready() -> void:
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)


func _process(_d: float) -> void:
	frame += 1
	var now := Time.get_ticks_usec()
	if frame > 1:
		frames.append(float(now - last) / 1000.0)
		var d: Dictionary = ZProf.us.duplicate()
		var rid := get_viewport().get_viewport_rid()
		d["_rcpu"] = int((RenderingServer.viewport_get_measured_render_time_cpu(rid) + RenderingServer.get_frame_setup_time_cpu()) * 1000.0)
		d["_gpu"] = int(RenderingServer.viewport_get_measured_render_time_gpu(rid) * 1000.0)
		zp.append(d)
	ZProf.us = {}
	last = now
	if frame == start_at:
		if cs.ps.is_empty() or cs.f < 0:
			start_at += 20   # (still loading)
		else:
			_setup()
	if cur != "" and frame == cur_frame + 5:
		_record()
	while not queue.is_empty() and int(queue[0][0]) <= frame:
		var q: Array = queue.pop_front()
		(q[1] as Callable).call()
	if frame > start_at and queue.is_empty() and cur == "" and not res.is_empty():
		_report()
		set_process(false)
		done.emit()


func _setup() -> void:
	cs.close_dialog()
	cs.cover.visible = false
	var f: int = cs.f
	for a in CState.armies_of(cs.ps, f):
		if int(a["busy"]) == 0 and my_army < 0:
			my_army = int(a["id"])
	if my_army < 0:
		print("TAPPROF no army")
		return
	var a0 := CState.army(cs.ps, my_army)
	cs.focus_region(int(a0["r"]), 1.2)
	print("TAPPROF setup pack=%s turn=%d f=%d army=%d (units %d) armies=%d mine=%d web=%s vp=%s scale=%.2f" % [
		str(cs.ps.get("pack", "rome")), int(cs.st["turn"]), f, my_army, CState.unit_count(a0), (cs.ps["armies"] as Array).size(),
		CState.armies_of(cs.ps, f).size(), OS.has_feature("web"), cs._vp(), get_viewport().get_final_transform().get_scale().x])
	var t := frame + 30
	for r in reps:
		t = _plan(t, "select_army", _army_pt, true)
		t = _plan(t, "bar_stance", func(): return _btn("stance"), false)
		t = _plan(t, "bar_details", func(): return _btn("details"), false)
		t = _plan(t, "side_close", _side_close, false)
		t = _plan(t, "deselect_army", _army_pt, true)
		t = _plan(t, "select_city", _city_pt, true)
		t = _plan(t, "deselect_btn", func(): return _ctl_center(cs.deselect_button), false)
		t = _plan(t, "end_turn_btn", func(): return _ctl_center(cs.end_button), false)
		t = _plan(t, "dialog_cancel", func(): return _dialog_btn(["Cancel", "Back", "Close"]), false)
	# last (it changes the state): End turn, then the warnings dialog's End turn: the turn resolves in that frame
	t = _plan(t, "end_turn_btn", func(): return _ctl_center(cs.end_button), false)
	t = _plan(t, "end_turn_confirm", func(): return _dialog_btn(["End turn"]), false)
	if ablate:
		t = _plan(t, "select_army", _army_pt, true)
		for r in reps:
			t = _call(t, "x_bar", func(): cs._refresh_bar())
			t = _call(t, "x_map6", func(): cs._refresh_map6())
			t = _call(t, "x_overlay", func(): cs.overlay.queue_redraw())
			t = _call(t, "x_mapview", func(): cs.map_view.queue_redraw())
			t = _call(t, "x_nothing", func(): pass)
	queue.sort_custom(func(x, y): return int(x[0]) < int(y[0]))


## A direct call at frame t, measured like a tap.
func _call(t: int, what: String, fn: Callable) -> int:
	queue.append([t, func():
		ZProf.us = {}
		var t0 := Time.get_ticks_usec()
		fn.call()
		h_us = Time.get_ticks_usec() - t0
		cur = what
		cur_frame = frame])
	return t + 40


## An action at frame t: press (touch or mouse) at the point, release 3 frames later; measured from the release.
func _plan(t: int, what: String, at: Callable, touch: bool) -> int:
	queue.append([t, func(): _press(what, at, touch, true)])
	queue.append([t + 3, func(): _press(what, at, touch, false)])
	return t + 40


func _press(what: String, at: Callable, touch: bool, down: bool) -> void:
	var p0: Vector2 = at.call()
	if p0.x < 0.0:
		if down:
			print("TAPPROF skip %s (no target)" % what)
		return
	var p := get_viewport().get_final_transform() * p0
	var ev: InputEvent
	if touch:
		var e := InputEventScreenTouch.new()
		e.index = 0
		e.position = p
		e.pressed = down
		ev = e
	else:
		var m := InputEventMouseButton.new()
		m.position = p
		m.global_position = p
		m.button_index = MOUSE_BUTTON_LEFT
		m.pressed = down
		m.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
		ev = m
		if down:
			var mm := InputEventMouseMotion.new()
			mm.position = p
			mm.global_position = p
			Input.parse_input_event(mm)
	if down:
		Input.parse_input_event(ev)
		Input.flush_buffered_events()
		return
	ZProf.us = {}
	var t0 := Time.get_ticks_usec()
	Input.parse_input_event(ev)
	Input.flush_buffered_events()
	h_us = Time.get_ticks_usec() - t0
	cur = what
	cur_frame = frame


func _record() -> void:
	# frames[i] is the frame that began at _process number i + 1; the handler ran in _process cur_frame.
	var i := cur_frame - 1
	if i < 0 or i >= frames.size():
		cur = ""
		return
	var fr: float = frames[i]
	var nx := 0.0
	for k in range(i + 1, mini(i + 4, frames.size())):
		nx = maxf(nx, float(frames[k]))
	if not res.has(cur):
		res[cur] = []
		order.append(cur)
	(res[cur] as Array).append([h_us / 1000.0, fr, nx, zp[i]])
	cur = ""


func _army_pt() -> Vector2:
	return cs.overlay.army_positions().get(my_army, Vector2(-1, -1))


func _btn(nm: String) -> Vector2:
	if cs.cmd_bar == null or not cs.cmd_bar.visible:
		return Vector2(-1, -1)
	for b in cs.cmd_bar.find_children("*", "Button", true, false):
		if str(b.name).contains(nm) and b.is_visible_in_tree():
			return _ctl_center(b)
	return Vector2(-1, -1)


func _city_pt() -> Vector2:
	var vp: Vector2 = cs._vp()
	var apos := _army_pt()
	for r in CState.regions_of(cs.ps, cs.f):
		var q: Vector2 = cs.overlay.to_screen(Geo.site(int(r)))
		if q.x > 100 and q.y > 100 and q.x < vp.x - 400 and q.y < vp.y - 250 and q.distance_to(apos) > 60.0:
			return q
	return Vector2(-1, -1)


func _side_close() -> Vector2:
	for b in cs.side.find_children("*", "Button", true, false):
		if (b as Button).text == "Close" and b.is_visible_in_tree():
			return _ctl_center(b)
	return Vector2(-1, -1)


func _dialog_btn(texts: Array) -> Vector2:
	if not cs.dialog.visible:
		return Vector2(-1, -1)
	for x in cs.dialog.find_children("*", "Button", true, false):
		if (x as Button).text in texts and x.is_visible_in_tree():
			return _ctl_center(x)
	return Vector2(-1, -1)


func _ctl_center(c: Control) -> Vector2:
	if c == null or not c.is_visible_in_tree():
		return Vector2(-1, -1)
	return c.get_global_rect().get_center()


func _report() -> void:
	var sorted := frames.slice(start_at)
	sorted.sort()
	var base: float = sorted[sorted.size() / 2] if not sorted.is_empty() else 0.0
	print("TAPPROF base %.2f ms (median frame, %d frames)" % [base, sorted.size()])
	print("TAPPROF %-15s %8s %8s %8s  layers of the frame (median ms)" % ["action", "handler", "frame", "next3"])
	for k in order:
		var rows: Array = res[k]
		var keys := {}
		for r in rows:
			for l in r[3]:
				keys[l] = true
		var lv: Array = []
		for l in keys:
			lv.append([_med(rows.map(func(r): return float(r[3].get(l, 0)) / 1000.0)), l])
		lv.sort_custom(func(x, y): return x[0] > y[0])
		var ls := ""
		for e in lv:
			if float(e[0]) >= 0.3:
				ls += " %s=%.1f" % [e[1], e[0]]
		print("TAPPROF %-15s %8.1f %8.1f %8.1f  n=%d |%s" % [k, _med(rows.map(func(r): return r[0])),
			_med(rows.map(func(r): return r[1])), _med(rows.map(func(r): return r[2])), rows.size(), ls])
	print("TAPPROF done")


static func _med(a: Array) -> float:
	if a.is_empty():
		return 0.0
	var b := a.duplicate()
	b.sort()
	return float(b[b.size() / 2])
