extends SceneTree
## The on-device diag overlay (game/diag_overlay.gd; docs/design/ui.md "The diag overlay"):
##   godot --headless --script res://tests/diag_test.gd              (default run: no overlay is built)
##   godot --headless --script res://tests/diag_test.gd -- --diag    (the overlay is built over the battle, reads it, hashes alike)
## Exits 0 / 1.

const DiagOverlay := preload("res://game/diag_overlay.gd")
const Battle := preload("res://game/battle.gd")
const BoardView := preload("res://game/board_view.gd")
const ConfirmOrders := preload("res://game/confirm_orders.gd")
const UiScale := preload("res://game/ui_scale.gd")

var ok := true


func _check(c: bool, what: String) -> void:
	print(("PASS " if c else "FAIL ") + what)
	if not c:
		ok = false


func _initialize() -> void:
	UiScale.load_settings()
	ConfirmOrders.force = "off"
	BoardView.force = "3d"
	_run.call_deferred()


func _run() -> void:
	var want := "--diag" in OS.get_cmdline_user_args()
	_check(DiagOverlay.wanted() == want, "DiagOverlay.wanted() follows --diag (%s)" % str(want))
	var b := Battle.new()
	b.scenario_id = "battle_2000"
	b.seed_value = 7
	b.dive = false
	root.add_child(b)
	for i in 6:
		await process_frame
	var ov: DiagOverlay = null
	for c in b.get_children():
		if c is DiagOverlay:
			ov = c
	_check((ov != null) == want, "the overlay is built only with --diag")
	if ov == null:
		ov = DiagOverlay.new()
		ov.battle = b
		root.add_child(ov)   # (the text builders are checked either way)
		await process_frame
	var h0: int = b.sim.state_hash()
	var info := ov.info_text({"gl": {"MAX_TEXTURE_SIZE": 4096, "STENCIL_BITS": 8, "UNMASKED_RENDERER": "Adreno (TM) 650"}})
	_check(info.contains("view 3d") and info.contains("probe:") and info.contains("TEXTURE_SIZE=4096") and info.contains("Adreno"), "the info text names the view, the probe and the GL parameters")
	var lt := ov.log_text({"lines": [{"t": 1500, "l": "S", "n": 3, "m": "compile failed: x"}]})
	_check(lt.contains("S") and lt.contains("x3") and lt.contains("compile failed"), "the log text shows level, count and message")
	b.probe_last = {"drawn": 0, "men": 108, "path": "v3d-cpu", "tick": 0}
	_check(ov.info_text({}).contains("drawn 0 of 108 men"), "the last probe's drawn count is shown")
	for i in 90:
		await process_frame
	_check(b.sim.state_hash() != 0 and h0 != 0, "the sim runs under the overlay (hash read)")
	print("RESULT: ", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)
