extends SceneTree
## The oblique pack's fetch state machine (game/oblique_pack.gd) with a stubbed HTTPRequest, mount and presence check:
##   godot --headless --script res://tests/oblique_pack_test.gd
## absent -> downloading -> loaded (the loaders told to look again), a cancel, a failed fetch (HTTP 404, a network
## error, a pack that will not mount, a pack that mounts without the sheets), a retry after a failure, wait(), and the
## URL (page directory, ?v= the stamp's ob: token), the default view's flow (`should_start`: a cancel asks again only at the
## next battle, a failure only on the player's Oblique pick; its notice once). Exits 0 on success, 1 on failure.

const ObliquePack := preload("res://game/oblique_pack.gd")
const SpriteOb := preload("res://game/sprite_ob.gd")
const KitOb := preload("res://game/kit_ob.gd")

var fails := 0
var checks := 0


class StubRequest extends Node:
	signal request_completed(result: int, code: int, headers: PackedStringArray, body: PackedByteArray)
	var download_file := ""
	var requested := ""
	var cancelled := false
	var start_error := OK
	var downloaded := 0
	var body_size := -1

	func request(u: String) -> int:
		requested = u
		return start_error

	func cancel_request() -> void:
		cancelled = true

	func get_downloaded_bytes() -> int:
		return downloaded

	func get_body_size() -> int:
		return body_size


var last: StubRequest = null
var mounted_ok := true
var mount_calls := 0
var sheets := false
var next_error := OK
var wrote := 0
var write_ok := true
var BODY := PackedByteArray([1, 2, 3])


func _check(ok: bool, msg: String) -> void:
	checks += 1
	if not ok:
		fails += 1
		print("FAIL: ", msg)


func _make() -> ObliquePack:
	var p := ObliquePack.new()
	p._ui = false
	p.make_request = func() -> Node:
		last = StubRequest.new()
		last.start_error = next_error
		return last
	p.write = func(_path: String, d: PackedByteArray) -> bool:
		wrote += d.size()
		return write_ok
	p.mount = func(_path: String) -> bool:
		mount_calls += 1
		if mounted_ok:
			sheets = true
		return mounted_ok
	p.present = func() -> bool: return sheets
	root.add_child(p)
	return p


func _init() -> void:
	# URL
	_check(ObliquePack.pack_url("https://x.dev/game/index.html?a=1#b", "2026 src:a ob:1234abcd") == "https://x.dev/game/oblique.pck?v=1234abcd", "url with ob token")
	_check(ObliquePack.pack_url("https://x.dev/", "2026T src:a") == "https://x.dev/oblique.pck?v=2026T", "url falls back to the stamp's first word")
	_check(ObliquePack.pack_url("https://x.dev/", "") == "https://x.dev/oblique.pck", "url without a stamp")

	# absent -> downloading -> loaded
	var p := _make()
	var seen: Array = []
	p.state_changed.connect(func(s): seen.append(s))
	var fin: Array = []
	p.finished.connect(func(ok): fin.append(ok))
	_check(p.state == ObliquePack.State.ABSENT, "starts absent")
	p._begin("https://x.dev/oblique.pck?v=1")
	_check(p.state == ObliquePack.State.DOWNLOADING, "downloading after begin")
	_check(last.requested == "https://x.dev/oblique.pck?v=1", "requested the url")
	last.downloaded = 500
	last.body_size = 1000
	var prog: Array = []
	p.progress.connect(func(d, t): prog.append([d, t]))
	p.poll()
	_check(prog == [[500, 1000]], "progress reported")
	var req := last
	req.request_completed.emit(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), BODY)
	_check(p.state == ObliquePack.State.LOADED, "loaded after a 200 and a mount")
	_check(mount_calls == 1 and wrote == 3, "body written and mounted once")
	_check(fin == [true], "finished(true)")
	_check(seen == [ObliquePack.State.DOWNLOADING, ObliquePack.State.LOADED], "state sequence")
	SpriteOb.reset()
	KitOb.reset()
	p.start()
	_check(p.state == ObliquePack.State.LOADED and last == req, "start with the sheets present does nothing")

	# cancel
	sheets = false
	mount_calls = 0
	var c := _make()
	c._begin("u")
	var cfin: Array = []
	c.finished.connect(func(ok): cfin.append(ok))
	var creq := last
	c.cancel()
	_check(c.state == ObliquePack.State.CANCELLED, "cancelled")
	_check(creq.cancelled, "request cancelled")
	_check(cfin == [false], "finished(false) on cancel")
	creq.request_completed.emit(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), BODY)
	_check(c.state == ObliquePack.State.CANCELLED and mount_calls == 0, "a late completion after cancel is ignored")
	c.cancel()
	_check(c.state == ObliquePack.State.CANCELLED, "cancel when idle is harmless")

	# failures
	var f := _make()
	f._begin("u")
	last.request_completed.emit(HTTPRequest.RESULT_SUCCESS, 404, PackedStringArray(), BODY)
	_check(f.state == ObliquePack.State.FAILED and mount_calls == 0, "404 fails without mounting")
	f._begin("u")
	last.request_completed.emit(HTTPRequest.RESULT_CANT_CONNECT, 0, PackedStringArray(), BODY)
	_check(f.state == ObliquePack.State.FAILED, "network error fails")
	mounted_ok = false
	f._begin("u")
	last.request_completed.emit(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), BODY)
	_check(f.state == ObliquePack.State.FAILED and mount_calls == 1, "a pack that will not mount fails")
	f._begin("u")
	next_error = ERR_CANT_CONNECT
	f._begin("u")
	_check(f.state == ObliquePack.State.FAILED, "a request that cannot start fails")
	next_error = OK
	write_ok = false
	f._begin("u")
	last.request_completed.emit(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), BODY)
	_check(f.state == ObliquePack.State.FAILED and mount_calls == 1, "a body that cannot be written fails without mounting")
	write_ok = true
	# mounts but the sheets are not in it
	mounted_ok = true
	var m := _make()
	m.mount = func(_path: String) -> bool: return true
	m._begin("u")
	last.request_completed.emit(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), BODY)
	_check(m.state == ObliquePack.State.FAILED, "mounted without the sheets fails")
	# retry after a failure succeeds
	mount_calls = 0
	f._begin("u")
	last.request_completed.emit(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), BODY)
	_check(f.state == ObliquePack.State.LOADED, "retry after failure loads")

	# the default view's flow (oblique by default, 2026-10-30): who may start a fetch after an attempt ended
	var St := ObliquePack.State
	_check(ObliquePack.should_start(St.ABSENT, false, false), "absent: the boot's ensure starts the fetch")
	_check(not ObliquePack.should_start(St.DOWNLOADING, true, true), "never a second fetch while one runs")
	_check(not ObliquePack.should_start(St.LOADED, true, true), "never once loaded")
	_check(not ObliquePack.should_start(St.CANCELLED, false, false), "cancelled: the menu does not ask again by itself")
	_check(ObliquePack.should_start(St.CANCELLED, false, true), "cancelled: the next battle's start asks once more")
	_check(ObliquePack.should_start(St.CANCELLED, true, false), "cancelled: the player's Oblique pick asks again")
	_check(not ObliquePack.should_start(St.FAILED, false, false), "failed: no retry at the menu")
	_check(not ObliquePack.should_start(St.FAILED, false, true), "failed: no retry at a battle (said once)")
	_check(ObliquePack.should_start(St.FAILED, true, false), "failed: the player's Oblique pick retries")
	# the failure notice: once a session
	ObliquePack.told_failed = false
	var n1 := _make()
	n1._begin("u")
	last.request_completed.emit(HTTPRequest.RESULT_SUCCESS, 404, PackedStringArray(), BODY)
	_check(ObliquePack.told_failed, "a failure sets the notice")
	n1._begin("u")
	last.request_completed.emit(HTTPRequest.RESULT_SUCCESS, 404, PackedStringArray(), BODY)
	_check(n1.state == St.FAILED and ObliquePack.told_failed, "a second failure: no second notice (still told)")
	var n2 := _make()
	n2._begin("u")
	n2.cancel()
	_check(n2.state == St.CANCELLED, "a cancel is not a failure")

	# wait(): returns at once when idle, after the end when downloading
	sheets = false
	var w := _make()
	var done := [false]
	var waiter := func() -> void:
		await w.wait()
		done[0] = true
	await_idle(w, waiter, done)
	print("oblique pack test: %d checks, %d failed" % [checks, fails])
	print("RESULT: ", "PASS" if fails == 0 else "FAIL")
	quit(0 if fails == 0 else 1)


func await_idle(w: ObliquePack, waiter: Callable, done: Array) -> void:
	waiter.call()
	_check(done[0], "wait() returns at once when nothing runs")
	done[0] = false
	w._begin("u")
	waiter.call()
	_check(not done[0], "wait() holds while downloading")
	last.request_completed.emit(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), BODY)
	_check(done[0], "wait() returns when the attempt ends")
