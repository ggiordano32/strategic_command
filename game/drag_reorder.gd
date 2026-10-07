extends Control
## Drag to reorder a list of controls: the battle's unit cards (hud.gd) and
## the unit rows of the campaign army card (campaign_panels.gd). One helper
## per list; every item forwards its gui_input events with feed(event, its
## index in `items`). The helper only reports; the owner reorders.
##
## Gestures (touches arrive as mouse events emulated from the touch, device
## DEVICE_ID_EMULATION; see touch_scroll.gd):
##  - mouse: press an item and move more than DRAG_SLOP: it lifts and the
##    drag begins. Held still for HOLD_SEC: `held` (the caller opens the
##    unit page) and the release presses nothing.
##  - touch: hold still LIFT_SEC: the item lifts (bigger, brighter, with a
##    shadow) and TouchScroll.hold keeps the list from scrolling; then drag.
##    Lifted and released without moving: `held`. A touch that moves before
##    it lifts is not ours (a TouchScroll scrolls it, or nothing happens).
## While dragging: a ghost of the item follows the pointer, a bar marks
## where it will go, and the pointer near an end of `scroll` scrolls it.
## The drop emits moved(from, to): the item's index before, and its index
## in the list after the move. Once an item is lifted its events are
## accepted here, so the item never sees the release (no press, no
## selection, no long press of its own: items may offer cancel_press()).
## The helper draws on top of the list (top_level, canvas coordinates; it
## lays nothing out and takes no input).

signal moved(from: int, to: int)
signal held(index: int)
signal lifted(index: int)

const TouchScroll := preload("res://game/touch_scroll.gd")

const LIFT_SEC := 0.35       # touch: hold still this long to pick an item up
const HOLD_SEC := 0.5        # mouse: hold still this long = long press
const DRAG_SLOP := 8.0       # mouse: px before a press becomes a drag
const LIFT_SLOP := 8.0       # touch: px the finger may wander before it lifts
const EDGE := 40.0           # px from a scroll area's end that auto-scroll
const SCROLL_SPEED := 700.0  # px/s at the very edge
const LIFT_SCALE := 1.08
const COL_MARK := Color(1.0, 0.85, 0.3)

## The items in display order (Controls).
var items: Array = []
## A column (marker above / below an item) rather than wrapping rows (left /
## right of an item).
var vertical := false
## Scrolled while the pointer is near its ends during a drag (optional).
var scroll: ScrollContainer = null

var _i := -1                 # item pressed (or lifted)
var _start := Vector2.ZERO
var _pos := Vector2.ZERO
var _t0 := 0.0
var _touch := false
var _lifted := false
var _dragging := false
var _swallow := -1           # item whose release must press nothing (after a hold)
var _eat: Control = null     # item whose touch release (ScreenTouch) must press nothing
var _holding := false        # we set TouchScroll.hold
var _slot := -1
var _mark := Rect2()
var _acc := 0.0
var _saved := {}             # the lifted item's look and rect


func _init() -> void:
	top_level = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 5


## True while an item is lifted (tests, owners).
func is_active() -> bool:
	return _lifted


func feed(e: InputEvent, i: int) -> void:
	if i < 0 or i >= items.size():
		return
	if e is InputEventScreenTouch or e is InputEventScreenDrag:
		# Buttons also take the touch itself (after its emulated mouse
		# events): once the gesture is ours, the item must not see it.
		if _eat == items[i] or (_lifted and i == _i):
			_accept(i)
			if e is InputEventScreenTouch and not (e as InputEventScreenTouch).pressed:
				_eat = null
		return
	if e is InputEventMouseButton:
		var mb := e as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		if mb.pressed:
			_end()
			_swallow = -1
			_eat = null
			_i = i
			_touch = TouchScroll.is_touch_event(mb)
			_start = _canvas(i, mb.position)
			_pos = _start
			_t0 = _now()
			return
		if _swallow == i:
			_swallow = -1
			_accept(i)
			_eat = items[i]
			return
		if _i < 0:
			return
		var it := _i
		if _dragging:
			_pos = _canvas(i, mb.position) if not _far(mb.position) else _pos
			var s := _find_slot(_pos)
			_accept(i)
			_eat = items[i]
			_end()
			if s >= 0:
				var to := s if s <= it else s - 1
				if to != it:
					moved.emit(it, to)
			return
		if _lifted:
			_accept(i)
			_eat = items[i]
			_end()
			held.emit(it)
			return
		_end()
		return
	if e is InputEventMouseMotion and _i >= 0 and i == _i:
		var mm := e as InputEventMouseMotion
		if _far(mm.position):
			# TouchScroll took the touch (it moves the pointer far away).
			if not _lifted:
				_end()
			return
		var p := _canvas(i, mm.position)
		if _lifted:
			_pos = p
			if not _dragging and p.distance_to(_start) > LIFT_SLOP:
				_dragging = true
			_accept(i)
			queue_redraw()
			return
		if p.distance_to(_start) > (LIFT_SLOP if _touch else DRAG_SLOP):
			if _touch:
				_end()  # moved before it lifted: a scroll (or nothing), not ours
			else:
				_lift()
				_dragging = true
				_pos = p
				_accept(i)


func _process(delta: float) -> void:
	if _i < 0:
		return
	if not (items[_i] as Control).is_visible_in_tree():
		_end()
		return
	if not _lifted:
		var t := _now() - _t0
		if _touch and t >= LIFT_SEC:
			_lift()
		elif not _touch and t >= HOLD_SEC:
			var it := _i
			_end()
			_swallow = it
			if items[it].has_method("cancel_press"):
				items[it].call("cancel_press")
			held.emit(it)
		return
	if _dragging:
		_autoscroll(delta)
		_slot = _find_slot(_pos)
		queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_EXIT_TREE and _holding:
		TouchScroll.hold = false
		_holding = false


func _lift() -> void:
	_lifted = true
	var c: Control = items[_i]
	_saved = {"scale": c.scale, "pivot": c.pivot_offset, "z": c.z_index, "mod": c.modulate, "rect": c.get_global_rect()}
	if c.has_method("cancel_press"):
		c.call("cancel_press")
	c.pivot_offset = c.size * 0.5
	c.scale = Vector2.ONE * LIFT_SCALE
	c.z_index = 10
	c.modulate = Color(1.25, 1.25, 1.25)
	if _touch:
		TouchScroll.hold = true
		_holding = true
	lifted.emit(_i)
	queue_redraw()


func _end() -> void:
	if _lifted and _i >= 0 and _i < items.size() and is_instance_valid(items[_i]):
		var c: Control = items[_i]
		c.scale = _saved["scale"]
		c.pivot_offset = _saved["pivot"]
		c.z_index = _saved["z"]
		c.modulate = _saved["mod"]
	if _holding:
		TouchScroll.hold = false
		_holding = false
	_i = -1
	_lifted = false
	_dragging = false
	_slot = -1
	_acc = 0.0
	queue_redraw()


func _accept(i: int) -> void:
	(items[i] as Control).accept_event()


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


## A pointer position TouchScroll moved far away (its scroll took over).
static func _far(local: Vector2) -> bool:
	return absf(local.x) > 50000.0 or absf(local.y) > 50000.0


## An event position local to item i, in canvas coordinates.
func _canvas(i: int, local: Vector2) -> Vector2:
	return (items[i] as Control).get_global_transform() * local


func _rect(k: int) -> Rect2:
	if _lifted and k == _i:
		return _saved["rect"]
	return (items[k] as Control).get_global_rect()


## The insertion slot (0 .. items.size()) nearest to p, and the marker rect.
func _find_slot(p: Vector2) -> int:
	var best := -1
	var bd := INF
	for k in items.size():
		var rk := _rect(k)
		var dx := maxf(maxf(rk.position.x - p.x, p.x - rk.end.x), 0.0)
		var dy := maxf(maxf(rk.position.y - p.y, p.y - rk.end.y), 0.0)
		var d := dx * dx + dy * dy
		if d < bd:
			bd = d
			best = k
	if best < 0:
		return -1
	var r := _rect(best)
	var after := p.y > r.get_center().y if vertical else p.x > r.get_center().x
	if vertical:
		_mark = Rect2(r.position.x, (r.end.y if after else r.position.y) - 2.0, r.size.x, 4.0)
	else:
		_mark = Rect2((r.end.x if after else r.position.x) - 2.0, r.position.y, 4.0, r.size.y)
	return best + (1 if after else 0)


func _autoscroll(delta: float) -> void:
	if scroll == null or not is_instance_valid(scroll) or not scroll.is_visible_in_tree():
		return
	var r := scroll.get_global_rect()
	var lo := r.position.y if vertical else r.position.x
	var hi := r.end.y if vertical else r.end.x
	var p := _pos.y if vertical else _pos.x
	var v := 0.0
	if p < lo + EDGE:
		v = -clampf((lo + EDGE - p) / EDGE, 0.0, 1.5)
	elif p > hi - EDGE:
		v = clampf((p - hi + EDGE) / EDGE, 0.0, 1.5)
	if v == 0.0:
		_acc = 0.0
		return
	_acc += v * SCROLL_SPEED * delta
	var iv := int(_acc)
	_acc -= iv
	if vertical:
		scroll.scroll_vertical += iv
	else:
		scroll.scroll_horizontal += iv


func _draw() -> void:
	if not _lifted or _i < 0:
		return
	var inv := get_global_transform().affine_inverse()
	var r: Rect2 = _saved["rect"]
	var big := r.grow_individual(r.size.x * (LIFT_SCALE - 1.0) * 0.5, r.size.y * (LIFT_SCALE - 1.0) * 0.5,
		r.size.x * (LIFT_SCALE - 1.0) * 0.5, r.size.y * (LIFT_SCALE - 1.0) * 0.5)
	draw_set_transform_matrix(inv)
	# Shadow and a gold edge round the lifted item (it draws above this
	# helper, so only the rim shows).
	draw_rect(Rect2(big.position + Vector2(2, 4), big.size).grow(3.0), Color(0, 0, 0, 0.55))
	draw_rect(big.grow(1.5), Color(COL_MARK, 0.9), false, 2.0)
	if not _dragging:
		return
	# Ghost following the pointer.
	var g := Rect2(_pos - r.size * 0.5, r.size)
	draw_rect(g, Color(1, 1, 1, 0.12))
	draw_rect(g, Color(COL_MARK, 0.8), false, 2.0)
	# Where it goes (nothing when the drop would leave it in place).
	if _slot >= 0 and _slot != _i and _slot != _i + 1:
		draw_rect(_mark, COL_MARK)
