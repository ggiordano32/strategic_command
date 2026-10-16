extends RefCounted
## Per-frame layer timing for the overworld (tests/zoom_sweep.gd): a layer adds the microseconds of its _process / _draw.
## Off unless a test sets `on`; costs one bool test per call otherwise.
static var on := false
static var us := {}

static func begin() -> int:
	return Time.get_ticks_usec() if on else 0

static func add(key: String, t0: int) -> void:
	if on:
		us[key] = int(us.get(key, 0)) + Time.get_ticks_usec() - t0
