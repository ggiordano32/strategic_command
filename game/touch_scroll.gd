extends ScrollContainer
## A ScrollContainer that scrolls by dragging anywhere in it on a touch
## screen, including on the buttons and rows inside it, with a fling. Every
## scrollable list in the game uses it.
##
## Why: buttons (and the unit rows) stop mouse events, so a finger that lands
## on one never reaches the ScrollContainer, whose own touch dragging only sees
## touches on gaps and labels. Here the container watches the pointer events
## itself in _input, before the GUI gets them:
##  - only touch-originated events count (the mouse events Godot emulates from
##    a touch carry device DEVICE_ID_EMULATION); a real mouse keeps the wheel
##    and immediate clicks;
##  - a touch inside the container that moves more than DEADZONE logical px
##    (along the scrollable axis that dominates) becomes a scroll: from then
##    on the pointer position the GUI sees is moved far outside, so the button
##    or row under the finger drops its pressed look and does not fire on
##    release (buttons fire on release when the finger is still inside), and a
##    long press in progress is cancelled the same way;
##  - the innermost TouchScroll under the finger that can scroll that way
##    takes the gesture; drags never reach the map or battle underneath (the
##    touch events of a scroll are marked handled);
##  - on release the scroll keeps its velocity and slows down (FRICTION).
## The built-in drag scrolling is switched off (huge scroll_deadzone) so the
## two never add up. Scroll bars become thin indicators on touch screens.

const UiScale := preload("res://game/ui_scale.gd")

const DEADZONE := 10.0        # logical px before a touch becomes a scroll
const FRICTION := 5.0         # fling velocity decays by e^-FRICTION per second
const MIN_FLING := 40.0       # px/s below which a fling stops
const OUTSIDE := Vector2(-100000.0, -100000.0)

static var _owner: ScrollContainer = null   # container scrolling the current touch

var _down := false
var _start := Vector2.ZERO
var _last := Vector2.ZERO
var _scrolling := false
var _vel := Vector2.ZERO
var _last_t := 0.0
var _fling := Vector2.ZERO
var _acc := Vector2.ZERO      # sub-pixel remainder of the scroll position


func _init() -> void:
	scroll_deadzone = 100000  # no built-in drag scrolling; see the header
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED


func _ready() -> void:
	if UiScale.is_touch():
		get_v_scroll_bar().custom_minimum_size.x = 4
		get_h_scroll_bar().custom_minimum_size.y = 4
		get_v_scroll_bar().mouse_filter = Control.MOUSE_FILTER_IGNORE
		get_h_scroll_bar().mouse_filter = Control.MOUSE_FILTER_IGNORE


static func is_touch_event(e: InputEvent) -> bool:
	return e.device == InputEvent.DEVICE_ID_EMULATION and (e is InputEventMouseButton or e is InputEventMouseMotion)


func _input(e: InputEvent) -> void:
	if not is_visible_in_tree():
		_down = false
		if _owner == self:
			_owner = null
		_scrolling = false
		return
	if e is InputEventScreenDrag and _scrolling:
		get_viewport().set_input_as_handled()  # never reaches the map underneath
		return
	if e is InputEventScreenTouch and _scrolling and not e.pressed:
		get_viewport().set_input_as_handled()
		return
	if not is_touch_event(e):
		return
	if e is InputEventMouseButton:
		var mb := e as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		if mb.pressed:
			_fling = Vector2.ZERO
			_owner = null  # a new touch: any earlier gesture is over
			_down = get_global_rect().has_point(mb.position)
			_scrolling = false
			_start = mb.position
			_last = mb.position
			_vel = Vector2.ZERO
			_last_t = Time.get_ticks_msec() / 1000.0
		else:
			if _scrolling:
				# The finger lifts after a scroll: the GUI sees the release far
				# away (no press), and the scroll flings on.
				mb.position = OUTSIDE
				mb.global_position = OUTSIDE
				_fling = _vel if _vel.length() > MIN_FLING else Vector2.ZERO
				_owner = null
			_down = false
			_scrolling = false
		return
	var mm := e as InputEventMouseMotion
	if not _down:
		return
	var now := Time.get_ticks_msec() / 1000.0
	if not _scrolling:
		var d := mm.position - _start
		var axis := _axis(d)
		if d.length() < DEADZONE or axis == Vector2.ZERO or _owner != null or _inner_claims(axis):
			return
		_scrolling = true
		_owner = self
		_last = mm.position
	var delta := mm.position - _last
	var dt := maxf(now - _last_t, 0.001)
	var inst := -delta / dt
	_vel = _vel.lerp(inst, 0.5)
	_last = mm.position
	_last_t = now
	_scroll_by(-delta)
	# The control under the finger must not see this as a press any more.
	mm.position = OUTSIDE
	mm.global_position = OUTSIDE


## The scrollable direction the drag d follows (zero if this container
## cannot scroll that way).
func _axis(d: Vector2) -> Vector2:
	var vb := get_v_scroll_bar()
	var hb := get_h_scroll_bar()
	var can_v := vertical_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED and vb.max_value > vb.page + 0.5
	var can_h := horizontal_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED and hb.max_value > hb.page + 0.5
	if absf(d.y) >= absf(d.x):
		return Vector2(0, 1) if can_v else Vector2.ZERO
	return Vector2(1, 0) if can_h else Vector2.ZERO


## A TouchScroll inside this one, under the start point, that can scroll
## along this axis takes the gesture instead.
func _inner_claims(axis: Vector2) -> bool:
	for c in find_children("*", "ScrollContainer", true, false):
		if c != self and c.get_script() == get_script() and c.get("_down") and (c as Control).is_visible_in_tree():
			var d: Vector2 = c.call("_axis", axis * 100.0)
			if d != Vector2.ZERO:
				return true
	return false


func _scroll_by(v: Vector2) -> void:
	_acc += v
	var iv := Vector2(int(_acc.x), int(_acc.y))
	_acc -= iv
	if iv.y != 0.0:
		scroll_vertical += int(iv.y)
	if iv.x != 0.0 and horizontal_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED:
		scroll_horizontal += int(iv.x)


func _process(delta: float) -> void:
	if _fling == Vector2.ZERO:
		return
	_scroll_by(_fling * delta)
	_fling *= exp(-FRICTION * delta)
	if _fling.length() < MIN_FLING:
		_fling = Vector2.ZERO


## True while a touch is scrolling this container (tests).
func is_scrolling() -> bool:
	return _scrolling


func is_flinging() -> bool:
	return _fling != Vector2.ZERO
