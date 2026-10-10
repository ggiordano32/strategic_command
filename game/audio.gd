extends Node
## Sound (docs/STATUS.md item 8b). Autoload "Audio". View only: nothing here
## touches the sim; the screens read sim events and call the static helpers
## (AudioFx.play / AudioFx.click / ..., AudioFx being the preload of this script), which do nothing when there is no
## instance (headless runs, tests) or the device cannot play yet.
##
## Mixing: sample players only (web Compatibility, threads off). Buses Master
## <- Effects, Ambient; Effects <- five pan buses (a Panner each, -1 .. 1) so
## a clip is placed left / right by picking a bus. Volumes (percent) and mute
## live in user://settings.cfg [audio] master / effects / ambient / mute.
## Caps: every call names a bucket; a bucket plays at most CAPS[bucket][0]
## clips per CAPS[bucket][1] ms (wall clock, view only), so a battle never
## stacks a sound per soldier. Web: nothing plays until the first tap / click
## / key (the browser keeps its audio context locked until then).

const SETTINGS := "user://settings.cfg"
const DIR := "res://game/sounds/"
const POOL := 14
const PANS := [-1.0, -0.5, 0.0, 0.5, 1.0]
const DEFAULTS := {"master": 80, "effects": 100, "ambient": 60}
## bucket -> [clips, window ms]
const CAPS := {
	"melee": [1, 100], "impact": [1, 100], "volley": [1, 100], "art": [2, 100], "state": [1, 100],
	"gate": [1, 150], "ladder": [1, 300], "beast": [1, 300], "horn": [1, 500], "ui": [3, 60],
}
const LOOPS := ["bed_battle", "bed_map", "fire_loop"]
const CLIPS := ["melee", "charge", "volley", "whoosh", "bolt_release", "bolt_impact", "stone_release",
	"stone_impact", "burst", "fire_loop", "gate_blow", "gate_break", "creak", "unit_break", "unit_rally",
	"horn_start", "horn_victory", "horn_defeat", "elephant", "dogs", "tap", "order_ok", "refused",
	"end_turn", "turn_resolved", "battle_pending", "chime", "bed_battle", "bed_map"]

var active := false      # a device is there (not headless)
var unlocked := false    # the first user input happened (always true off the web)
var muted := false
var vol := {"master": 80, "effects": 100, "ambient": 60}

var _streams := {}
var _pool: Array[AudioStreamPlayer] = []
var _next := 0
var _pan_bus := PackedStringArray()
var _bed: AudioStreamPlayer
var _fire: AudioStreamPlayer
var _bed_name := ""
var _battle_depth := 0
var _fire_target := 0.0
var _stamps := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_settings()
	active = DisplayServer.get_name() != "headless" and AudioServer.get_output_device() != ""
	unlocked = not OS.has_feature("web")
	if not active:
		set_process(false)
		set_process_input(false)
		return
	_build_buses()
	for n in CLIPS:
		var s = load(DIR + n + ".wav")
		if s is AudioStreamWAV:
			if n in LOOPS:
				s = s.duplicate()
				s.loop_mode = AudioStreamWAV.LOOP_FORWARD
				s.loop_begin = 0
				s.loop_end = (s.data.size() / 2) - 1
			_streams[n] = s
	for i in POOL:
		var p := AudioStreamPlayer.new()
		p.bus = "Effects"
		add_child(p)
		_pool.append(p)
	_bed = AudioStreamPlayer.new()
	_bed.bus = "Ambient"
	add_child(_bed)
	_fire = AudioStreamPlayer.new()
	_fire.bus = "Ambient"
	_fire.stream = _streams.get("fire_loop")
	_fire.volume_db = -80.0
	add_child(_fire)
	apply_volumes()
	if unlocked:
		_refresh_bed()


func _build_buses() -> void:
	for b in ["Effects", "Ambient"]:
		if AudioServer.get_bus_index(b) < 0:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, b)
			AudioServer.set_bus_send(i, "Master")
	for k in PANS.size():
		var nm := "FxPan%d" % k
		_pan_bus.append(nm)
		if AudioServer.get_bus_index(nm) >= 0:
			continue
		AudioServer.add_bus()
		var i := AudioServer.bus_count - 1
		AudioServer.set_bus_name(i, nm)
		AudioServer.set_bus_send(i, "Effects")
		var pe := AudioEffectPanner.new()
		pe.pan = PANS[k]
		AudioServer.add_bus_effect(i, pe)


func _input(event: InputEvent) -> void:
	if unlocked:
		return
	if (event is InputEventMouseButton and event.pressed) or (event is InputEventScreenTouch and event.pressed) \
			or (event is InputEventKey and event.pressed):
		unlocked = true
		_refresh_bed()


func _process(delta: float) -> void:
	if _fire != null and unlocked:
		var v := _fire_target * 0.55
		var cur := db_to_linear(_fire.volume_db) if _fire.playing else 0.0
		cur = move_toward(cur, v, delta * 1.5)
		if cur < 0.01:
			if _fire.playing:
				_fire.stop()
		else:
			if not _fire.playing:
				_fire.play()
			_fire.volume_db = linear_to_db(cur)


# ---------------------------------------------------------------- settings --

func load_settings() -> void:
	var cf := ConfigFile.new()
	cf.load(SETTINGS)
	for k in DEFAULTS:
		vol[k] = clampi(int(cf.get_value("audio", k, DEFAULTS[k])), 0, 100)
	muted = int(cf.get_value("audio", "mute", 0)) != 0


func save_settings() -> void:
	var cf := ConfigFile.new()
	cf.load(SETTINGS)
	for k in DEFAULTS:
		cf.set_value("audio", k, int(vol[k]))
	cf.set_value("audio", "mute", 1 if muted else 0)
	cf.save(SETTINGS)


func apply_volumes() -> void:
	if not active:
		return
	AudioServer.set_bus_mute(0, muted)
	AudioServer.set_bus_volume_db(0, _db(vol["master"]))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Effects"), _db(vol["effects"]))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Ambient"), _db(vol["ambient"]))


static func _db(pct: int) -> float:
	return -80.0 if pct <= 0 else linear_to_db(pct / 100.0)


## Settings rows: set one of "master" / "effects" / "ambient" (percent).
func set_volume(key: String, pct: int) -> void:
	vol[key] = clampi(pct, 0, 100)
	apply_volumes()
	save_settings()


func set_muted(m: bool) -> void:
	muted = m
	apply_volumes()
	save_settings()


# -------------------------------------------------------------------- play --

func _play(clip: String, v: float, pan: float, bucket: String) -> void:
	if not active or not unlocked or muted or v < 0.04:
		return
	var s: AudioStream = _streams.get(clip)
	if s == null:
		return
	if bucket != "":
		var cap: Array = CAPS.get(bucket, [2, 100])
		var now := Time.get_ticks_msec()
		var st: Array = _stamps.get(bucket, [])
		while not st.is_empty() and now - int(st[0]) >= int(cap[1]):
			st.pop_front()
		if st.size() >= int(cap[0]):
			_stamps[bucket] = st
			return
		st.append(now)
		_stamps[bucket] = st
	var p := _pool[_next]
	_next = (_next + 1) % POOL
	p.stream = s
	p.volume_db = linear_to_db(clampf(v, 0.0, 1.0))
	var k := clampi(int(roundf((clampf(pan, -1.0, 1.0) + 1.0) * 2.0)), 0, 4)
	p.bus = _pan_bus[k]
	p.play()


func _refresh_bed() -> void:
	if _bed == null or not unlocked:
		return
	var want := "bed_battle" if _battle_depth > 0 else "bed_map"
	if want == _bed_name and _bed.playing:
		return
	_bed_name = want
	_bed.stream = _streams.get(want)
	if _bed.stream != null:
		_bed.play()
	if _battle_depth == 0:
		_fire_target = 0.0


# ----------------------------------------------------------------- statics --

static func inst() -> Node:
	var ml := Engine.get_main_loop()
	if ml is SceneTree:
		return (ml as SceneTree).root.get_node_or_null("Audio")
	return null


## True when sounds can play here (the battle skips its event tracking if not).
static func on() -> bool:
	var a = inst()
	return a != null and a.active


## Play a clip. bucket: the cap category (see CAPS); v 0..1; pan -1..1.
static func play(clip: String, v: float = 1.0, pan: float = 0.0, bucket: String = "") -> void:
	var a = inst()
	if a != null:
		a._play(clip, v, pan, bucket)


static func click() -> void:
	play("tap", 0.8, 0.0, "ui")


static func enter_battle() -> void:
	var a = inst()
	if a != null:
		a._battle_depth += 1
		a._refresh_bed()


static func leave_battle() -> void:
	var a = inst()
	if a != null:
		a._battle_depth = maxi(a._battle_depth - 1, 0)
		a._refresh_bed()


## Fire crackle bed level 0..1 (the battle: nearest burning unit).
static func fire_level(l: float) -> void:
	var a = inst()
	if a != null:
		a._fire_target = clampf(l, 0.0, 1.0)
