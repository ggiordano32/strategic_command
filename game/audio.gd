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
##
## Web: Sample playback (the web default: the browser plays each clip, no
## mixing in wasm). Bus volumes and mute apply there, bus effects do not, so
## the Panner does nothing and clips play centred on the web. The buses are
## made with bus_count, never add_bus() (see _build_buses).
##
## ?audio-debug=1 (web URL) or -- --audio-debug=1 (command line): a small
## label at the top left ("audio: <playback type>, context <state>, last
## clip <name> playing <yes/no>"), AUDIODEBUG console lines (the bus list,
## each clip played, its position 200 ms and 1.4 s later), and a test horn
## on the first input. View only, off by default; server/cmd/webcheck reads
## it (checkAudio).

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
	"end_turn", "turn_resolved", "battle_pending", "chime", "bed_battle", "bed_map", "musket", "cannon"]

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
var debug := false
var _dbg_label: Label
var _dbg_last := "-"
var _dbg_playing := false
var _dbg_sample := -1     # the last clip went through Sample playback: 1 / 0, -1 none yet


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_settings()
	active = DisplayServer.get_name() != "headless" and AudioServer.get_output_device() != ""
	unlocked = not OS.has_feature("web")
	for a in _launch_args():
		if a == "--audio-debug=1" or a == "--audio-debug":
			debug = true
	if debug:
		_dbg_start()
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
	if debug:
		_dbg_dump("ready")


## Master <- Effects, Ambient; Effects <- FxPan0..4. Grown with bus_count,
## never AudioServer.add_bus(): on the web (Sample playback) Godot 4.7's
## add_bus() puts the new bus at the wrong place in the browser's copy of
## the bus list (it inserts it before the last bus instead of appending it),
## the next set_bus_send then makes Master send into a child bus, and
## nothing reaches the speakers. set_bus_count appends in order on both
## sides. Native: the same buses either way.
func _build_buses() -> void:
	var names := ["Effects", "Ambient"]
	for k in PANS.size():
		names.append("FxPan%d" % k)
		_pan_bus.append("FxPan%d" % k)
	for nm: String in names:
		if AudioServer.get_bus_index(nm) >= 0:
			continue
		var i := AudioServer.bus_count
		AudioServer.bus_count = i + 1
		AudioServer.set_bus_name(i, nm)
		if nm.begins_with("FxPan"):
			AudioServer.set_bus_send(i, "Effects")
			var pe := AudioEffectPanner.new()
			pe.pan = PANS[int(nm.substr(5))]
			AudioServer.add_bus_effect(i, pe)
		else:
			AudioServer.set_bus_send(i, "Master")


func _input(event: InputEvent) -> void:
	if unlocked:
		return
	if (event is InputEventMouseButton and event.pressed) or (event is InputEventScreenTouch and event.pressed) \
			or (event is InputEventKey and event.pressed):
		unlocked = true
		_refresh_bed()
		if debug:
			_dbg_dump("unlock")
			_play("horn_start", 1.0, 0.0, "")


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
		if debug:
			print("AUDIODEBUG skip clip=%s active=%s unlocked=%s muted=%s v=%.2f" % [clip, active, unlocked, muted, v])
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
	if debug:
		_dbg_after_play(p, clip)


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


# --------------------------------------------- ?audio-debug=1 (view only) --

## On the web: wraps a few Web Audio calls so the page's AudioContext (the
## one Godot plays through) can be read: its state, rate, clock, the clips
## the browser started and the resume() calls.
const _JS_HOOK := """(function(){
 if (window.__scAudio) return;
 var A = window.__scAudio = {ctx: null, starts: 0, resumes: 0};
 var oc = AudioNode.prototype.connect;
 AudioNode.prototype.connect = function(){ if (!A.ctx) A.ctx = this.context; return oc.apply(this, arguments); };
 var os = AudioBufferSourceNode.prototype.start;
 AudioBufferSourceNode.prototype.start = function(){ A.starts++; if (!A.ctx) A.ctx = this.context; return os.apply(this, arguments); };
 var orr = AudioContext.prototype.resume;
 AudioContext.prototype.resume = function(){ A.resumes++; return orr.apply(this, arguments); };
 window.__scAudioStatus = function(){ var c = A.ctx;
  return JSON.stringify({state: c ? c.state : 'unknown', rate: c ? c.sampleRate : 0,
   time: c ? Math.round(c.currentTime * 100) / 100 : 0, starts: A.starts, resumes: A.resumes}); };
})()"""


## The command line's user args plus, on the web, the page URL's query.
static func _launch_args() -> Array:
	var args := Array(OS.get_cmdline_user_args())
	if OS.has_feature("web"):
		var q = JavaScriptBridge.eval("window.location.search", true)
		if q is String and q.length() > 1:
			for kv in (q as String).substr(1).split("&"):
				args.append("--" + kv)
	return args


func _dbg_start() -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.eval(_JS_HOOK, true)
	var cl := CanvasLayer.new()
	cl.layer = 120
	add_child(cl)
	_dbg_label = Label.new()
	_dbg_label.position = Vector2(8, 8)
	_dbg_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dbg_label.add_theme_font_size_override("font_size", 14)
	_dbg_label.add_theme_color_override("font_color", Color(1, 1, 0.6))
	_dbg_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_dbg_label.add_theme_constant_override("outline_size", 4)
	cl.add_child(_dbg_label)
	var t := Timer.new()
	t.wait_time = 0.5
	t.autostart = true
	t.timeout.connect(_dbg_refresh)
	add_child(t)


func _dbg_ctx() -> Dictionary:
	if not OS.has_feature("web"):
		return {"state": "native"}
	var d = JSON.parse_string(str(JavaScriptBridge.eval("window.__scAudioStatus ? window.__scAudioStatus() : '{}'", true)))
	return d if d is Dictionary else {}


## The playback type in effect, as seen on the last clip played (whether
## its stream is registered as a sample): ProjectSettings does not show the
## web's default (Sample, the engine's own .web override) to scripts.
func _dbg_type() -> String:
	return ["no clip yet", "Stream", "Sample"][_dbg_sample + 1]


func _dbg_refresh() -> void:
	if _dbg_label == null:
		return
	var c := _dbg_ctx()
	_dbg_label.text = "audio: %s, context %s, last clip %s playing %s\n%d Hz, %d started, %d resume, %s" % [_dbg_type(),
		c.get("state", "?"), _dbg_last, "yes" if _dbg_playing else "no", int(c.get("rate", AudioServer.get_mix_rate())),
		int(c.get("starts", 0)), int(c.get("resumes", 0)),
		"muted" if muted else "vol %d/%d/%d" % [vol["master"], vol["effects"], vol["ambient"]]]


func _dbg_dump(why: String) -> void:
	var buses := []
	for i in AudioServer.bus_count:
		buses.append("%s->%s fx%d %.1fdB%s" % [AudioServer.get_bus_name(i), AudioServer.get_bus_send(i),
			AudioServer.get_bus_effect_count(i), AudioServer.get_bus_volume_db(i), " MUTE" if AudioServer.is_bus_mute(i) else ""])
	print("AUDIODEBUG %s type=%s mix=%d speaker=%d latency=%.3f unlocked=%s muted=%s vol=%d/%d/%d buses=[%s] ctx=%s" % [why,
		_dbg_type(), AudioServer.get_mix_rate(), AudioServer.get_speaker_mode(), AudioServer.get_output_latency(),
		unlocked, muted, vol["master"], vol["effects"], vol["ambient"], ", ".join(buses), JSON.stringify(_dbg_ctx())])
	_dbg_refresh()


## The clip, its bus, playing right after play(), and the position 200 ms
## and 1.4 s later. Sample playback on the web reports the position from a
## worklet that holds it at the first block for the first second of the
## context's clock after the start, so only the 1.4 s reading shows it
## advancing there.
func _dbg_after_play(p: AudioStreamPlayer, clip: String) -> void:
	_dbg_last = clip
	var on0 := p.playing
	_dbg_playing = on0
	var pos0 := p.get_playback_position()
	var st := p.stream
	var sample := AudioServer.is_stream_registered_as_sample(st)
	_dbg_sample = 1 if sample else 0
	await get_tree().create_timer(0.2, true, false, true).timeout
	var pos200 := p.get_playback_position()
	var on200 := p.playing and p.stream == st
	_dbg_playing = on200
	_dbg_refresh()
	await get_tree().create_timer(1.2, true, false, true).timeout
	var pos1400 := p.get_playback_position() if p.stream == st else -1.0
	print("AUDIODEBUG play clip=%s bus=%s playing=%s pos0=%.3f pos200=%.3f pos1400=%.3f playing200=%s sample=%s ctx=%s" % [clip,
		p.bus, on0, pos0, pos200, pos1400, on200, sample, JSON.stringify(_dbg_ctx())])
	_dbg_playing = p.playing and p.stream == st
	_dbg_refresh()
