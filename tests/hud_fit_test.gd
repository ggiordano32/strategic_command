extends SceneTree
## The battle HUD pass (docs/design/ui.md "The battle HUD pass"): the bottom bar fits at three sizes with a selection of
## each role, a mixed selection and a stress selection (every chip applicable), and nothing is lost.
##   godot --path . --resolution 1280x720 -s tests/hud_fit_test.gd [-- --shots=DIR]
## At 844x390 (phone landscape, touch, dpr 3), 1180x820 (tablet) and 1280x720 (desktop) it asserts that no visible
## control of the bottom bar's rows extends past the viewport, the capsule and the actions do not overlap, Halt and
## Withdraw (and Run unless only guns are selected) are on the bar, every applicable chip is either on the bar or
## under More (never both, never clipped), the More popover stays inside the viewport, the phone capsule shows role
## glyphs and the desktop one words; the chips' states (cycle, Mixed, Pistols two-state, armed text), the cards'
## state strip and a resize with a selection standing. --shots=DIR saves screenshots. Exits 0 / 1.

const Battle := preload("res://game/battle.gd")
const BattleSim := preload("res://sim/battle_sim.gd")
const Scenarios := preload("res://sim/scenarios.gd")
const UT := preload("res://sim/unit_types.gd")
const MapGen := preload("res://sim/mapgen.gd")
const Terrain := preload("res://sim/terrain.gd")
const Kit := preload("res://game/campaign/ui_kit.gd")
const UiScale := preload("res://game/ui_scale.gd")
const AbilityChip := preload("res://game/ability_chip.gd")
const Traits := preload("res://game/unit_traits.gd")

const SIZES := [[780, 360, true], [844, 390, true], [393, 851, true], [1180, 820, false], [1280, 720, false], [2560, 1440, false]]
const GAP := 5.0

var _wd := 0
var _wd_all := 0

var failures := 0
var _shots := ""
var b
var _size_name := ""


func _check(c: bool, what: String) -> void:
	print(("PASS " if c else "FAIL ") + what)
	if not c:
		failures += 1


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			_shots = a.get_slice("=", 1)
	Kit.anim_override = 0
	if _shots != "":
		DirAccess.make_dir_recursive_absolute(_shots)
	_run.call_deferred()


func _resize(w: int, h: int, phone: bool) -> void:
	UiScale._dpr_override = 3.0 if phone else 1.0
	UiScale._touch_override = 1 if phone else 0
	DisplayServer.window_set_size(Vector2i(w, h))
	root.size = Vector2i(w, h)
	await _frames(6)
	UiScale.apply(root)
	await _frames(4)


## The first ground type of each role, preferring the row with the most abilities (so the chips show up).
func _types_by_role() -> Dictionary:
	var out := {}
	var best := {}
	for ty in UT.TYPES.size():
		var r := UT.role(ty)
		if r == "" or UT.stat(ty, "fixed") != 0 or UT.base_of(ty) != ty:
			continue
		var n := 0
		var m := UT.abilities(ty)
		for k in UT.AB_N:
			n += (m >> k) & 1
		if not out.has(r) or n > int(best[r]):
			out[r] = ty
			best[r] = n
	return out


func _scenario(by_role: Dictionary) -> Dictionary:
	var units: Array = []
	var x := 60
	for r in by_role:
		units.append(Scenarios.unit(0, int(by_role[r]), 40, x, 150, 0))
		x += 14
	units.append(Scenarios.unit(1, UT.index_of("spear"), 80, 150, 40, 512))
	var sc := Scenarios._test(units, [])
	sc["ai_sides"] = [1]
	return sc


func _new_battle(sc: Dictionary, side := 0) -> void:
	if is_instance_valid(b):
		b.free()
	b = Battle.new()
	b.custom_scenario = sc
	b.player_side = side
	b.seed_value = 5
	b.speed_q = 4
	root.add_child(b)
	await _frames(8)
	b._set_paused(true)


func _select_types(roles: Array, _by_role: Dictionary) -> void:
	var us: Array[int] = []
	for u in b.sim.n_units:
		if b.sim.u_side[u] != 0:
			continue
		if roles.is_empty() or roles.has(UT.role(b.sim.u_otype[u])):
			us.append(u)
	await _pick(us)


func _pick(us: Array[int]) -> void:
	b.selection.clear()
	b.selection.append_array(us)
	b.selected = us[0] if not us.is_empty() else -1
	b._selection_changed()
	await _frames(3)


func _rect_in(c: Control, vp: Vector2) -> bool:
	var r := c.get_global_rect()
	return r.position.x >= -0.5 and r.position.y >= -0.5 and r.end.x <= vp.x + 0.5 and r.end.y <= vp.y + 0.5


func _fit(label: String, expect_run := true) -> void:
	var h = b.hud
	var vp: Vector2 = root.get_visible_rect().size
	var bad: Array[String] = []
	var fixed_ok: bool = h.halt_button.is_visible_in_tree() and h.withdraw_button.is_visible_in_tree() \
		and (h.run_button.is_visible_in_tree() or not expect_run)
	var onbar := 0
	var under := 0

	for c in h._chip_order:
		var ch: AbilityChip = c
		if not ch.visible:
			continue
		var in_bar: bool = ch.get_parent() == h.chips_box or ch.get_parent() == h.chips_up
		var in_more: bool = ch.get_parent() == h.more_box
		if in_bar:
			onbar += 1
			if not ch.is_visible_in_tree() or not _rect_in(ch, vp):
				bad.append("%s off screen %s" % [ch.key, str(ch.get_global_rect())])
		elif in_more:
			under += 1
		else:

			bad.append(ch.key + " nowhere")
	for ctl in [h.halt_button, h.run_button, h.withdraw_button, h.more_button, h.group_box]:
		if (ctl as Control).is_visible_in_tree() and not _rect_in(ctl, vp):
			bad.append("%s past the viewport %s of %s" % [ctl.name, str((ctl as Control).get_global_rect()), str(vp)])
	if h.actions_box.is_visible_in_tree() and h.group_box.is_visible_in_tree():
		if h.actions_box.get_global_rect().position.x < h.group_box.get_global_rect().end.x - 0.5:
			bad.append("actions overlap the capsule")
	if h.withdraw_button.is_visible_in_tree():
		var wr: Rect2 = h.withdraw_button.get_global_rect()
		var br: Rect2 = h._bottom.get_global_rect()
		var right_ok: bool = wr.end.x <= br.end.x + 0.5 and wr.end.x >= br.end.x - GAP - 2.0
		for c in h._chip_order:
			if (c as Control).is_visible_in_tree() and c.get_parent() != h.chips_up and (c as Control).get_global_rect().end.x > wr.position.x + 0.5:
				right_ok = false
		if h.more_button.is_visible_in_tree() and h.more_button.get_global_rect().end.x > wr.position.x + 0.5:
			right_ok = false
		_check(right_ok, "%s %s: Withdraw at the bar's right edge, right of every chip and More (%s, bar %s)" % [_size_name, label, str(wr), str(br)])
	if under > 0 and not h.more_button.visible:
		bad.append("chips under More but no More")
	if under == 0 and h.more_button.visible:
		bad.append("More with nothing under it")
	_clusters_check(label)
	_two_rows_check(label)
	if not bad.is_empty():
		_dump()
	_check(fixed_ok, "%s %s: Halt, Withdraw (and Run) on the bar" % [_size_name, label])
	_check(bad.is_empty(), "%s %s: %d chips on the bar, %d under More, none clipped (%s)" % [_size_name, label, onbar, under, ", ".join(bad)])
	if h.more_button.visible:
		h._set_more_open(true)
		await _frames(2)
		_check(h.more_panel.visible and _rect_in(h.more_panel, vp), "%s %s: the More popover is open and inside the viewport (%s)" % [_size_name, label, str(h.more_panel.get_global_rect())])
		var kids_ok := true
		for c in h.more_box.get_children():
			if (c as Control).visible and not h.more_panel.get_global_rect().grow(0.5).encloses((c as Control).get_global_rect()):
				kids_ok = false
		_check(kids_ok, "%s %s: every chip under More sits inside the popover" % [_size_name, label])
		_more_headings_check(label)
		h._set_more_open(false)
		await _frames(1)


## The clusters of the bar (docs/design/ui.md "Chip clusters"): a caption for each cluster that has a chip on the bar and
## for no other, inside the chips box, the bar and the viewport and under (never over) a chip; a divider between two
## neighbouring clusters, none for a single cluster; the dividers inside the box and over no chip.
func _clusters_check(label: String) -> void:
	var h = b.hud
	var vp: Vector2 = root.get_visible_rect().size
	var present := {}
	var bar_chips: Array = []
	var rows_of := {}   # cluster -> {row index: true}
	var n_div := 0
	var boxes: Array = [h.chips_box, h.chips_up]
	for bi in 2:   # (the upper row first: it is read first)
		var prev := ""
		for c in (boxes[bi] as Control).get_children():   # (in the bar's left-to-right order)
			if c is AbilityChip and (c as Control).visible:
				var cl: String = h.cluster_of(c)
				present[cl] = true
				if not rows_of.has(cl):
					rows_of[cl] = {}
				rows_of[cl][bi] = true
				bar_chips.append(c)
				if prev != "" and cl != prev:
					n_div += 1
				prev = cl
	var caps: Dictionary = h.cluster_caption_rects()
	var bad: Array[String] = []
	var want: Array = present.keys()
	want.sort()
	var have: Array = caps.keys()
	have.sort()
	if want != have:
		bad.append("captions %s for clusters %s" % [str(have), str(want)])
	for cl in rows_of:
		if (rows_of[cl] as Dictionary).size() > 1:
			bad.append("cluster %s split across the rows" % cl)
	var box: Rect2 = h.chips_box.get_global_rect()
	if h.chips_up.visible:
		box = box.merge(h.chips_up.get_global_rect())
	var bar: Rect2 = h._bottom.get_global_rect()
	for k in caps:
		var r: Rect2 = caps[k]
		if not box.grow(0.5).encloses(r) or not bar.grow(0.5).encloses(r) or not Rect2(Vector2.ZERO, vp).grow(0.5).encloses(r):
			bad.append("caption %s outside (%s, box %s)" % [k, str(r), str(box)])
		for c in bar_chips:
			if r.intersects((c as Control).get_global_rect().grow(-0.5)):
				bad.append("caption %s over chip %s" % [k, c.key])
	var divs: Array = h.divider_rects()
	if divs.size() != n_div:
		bad.append("%d dividers for %d cluster joins" % [divs.size(), n_div])
	for r in divs:
		if not box.grow(0.5).encloses(r) or not Rect2(Vector2.ZERO, vp).grow(0.5).encloses(r):
			bad.append("divider outside %s" % str(r))
		for c in bar_chips:
			if (r as Rect2).intersects((c as Control).get_global_rect().grow(-0.5)):
				bad.append("divider over chip %s" % c.key)
	# The clusters follow one another in each row, left to right, in the fixed order.
	for bi in 2:
		var last := -1
		for c in (boxes[bi] as Control).get_children():
			if c is AbilityChip and (c as Control).visible:
				var ci: int = h.CLUSTERS.find(h.cluster_of(c))
				if ci < last:
					bad.append("chip %s out of cluster order" % c.key)
				last = maxi(last, ci)
	_check(bad.is_empty(), "%s %s: %d captions and %d dividers for %d clusters, inside the bar and clear of the chips (%s)" % [
		_size_name, label, caps.size(), divs.size(), present.size(), ", ".join(bad)])


## The double stack: while it is on, the upper row sits above the lower row, inside the viewport, clear of the cards, the
## capsule and the lower row; chips are 36 px high, the rows' captions fit between; bottom_height() covers the bar's
## top; off, the upper row is hidden and the chips are 42 high.
func _two_rows_check(label: String) -> void:
	var h = b.hud
	var vp: Vector2 = root.get_visible_rect().size
	var bad: Array[String] = []
	var up_n := 0
	for c in h.chips_up.get_children():
		if c is AbilityChip and (c as Control).visible:
			up_n += 1
	if h.two_rows != (up_n > 0):
		bad.append("two_rows %s with %d chips up" % [str(h.two_rows), up_n])
	if h.two_rows:
		var up: Rect2 = h.chips_up.get_global_rect()
		if not h.chips_up.is_visible_in_tree():
			bad.append("upper row hidden")
		if not Rect2(Vector2.ZERO, vp).grow(0.5).encloses(up):
			bad.append("upper row outside the viewport %s" % str(up))
		if up.end.y > h.chips_box.get_global_rect().position.y + 0.5:
			bad.append("upper row over the lower row %s %s" % [str(up), str(h.chips_box.get_global_rect())])
		if h.cards_bar.visible and up.intersects(h.cards_bar.get_global_rect().grow(-0.5)):
			bad.append("upper row over the cards")
		if h.group_box.is_visible_in_tree() and up.intersects(h.group_box.get_global_rect().grow(-0.5)):
			bad.append("upper row over the capsule")
		if h.actions_box.get_global_rect().position.y < up.end.y - 0.5:
			bad.append("actions over the upper row")
		for c in h._chip_order:
			if (c as Control).is_visible_in_tree() and c.get_parent() in [h.chips_box, h.chips_up] and absf((c as Control).size.y - 36.0) > 0.5:
				bad.append("chip %s %.0f high" % [c.key, (c as Control).size.y])
		if h._bottom.get_global_rect().position.y < vp.y - h.bottom_height() - 1.0:
			bad.append("bottom_height %.0f smaller than the bar %s" % [h.bottom_height(), str(h._bottom.get_global_rect())])
	else:
		if h.chips_up.visible:
			bad.append("upper row shown with one row")
		for c in h._chip_order:
			if (c as Control).visible and c.get_parent() == h.chips_box and absf((c as Control).size.y - 42.0) > 0.5:
				bad.append("chip %s %.0f high" % [c.key, (c as Control).size.y])
	_check(bad.is_empty(), "%s %s: double stack %s (%d chips up), bar %.0f px (%s)" % [
		_size_name, label, "on" if h.two_rows else "off", up_n, h.bottom_height(), ", ".join(bad)])


## The More popover's headings: one per cluster that has a chip under More, inside the viewport and the popover.
func _more_headings_check(label: String) -> void:
	var h = b.hud
	var vp: Vector2 = root.get_visible_rect().size
	var present := {}
	for c in h._chip_order:
		if (c as Control).visible and c.get_parent() == h.more_box:
			present[h.cluster_of(c)] = true
	var heads := {}
	var bad: Array[String] = []
	for k in h.more_box.get_children():
		if str(k.name).begins_with("head_"):
			heads[str(k.name).substr(5)] = true
			var r: Rect2 = (k as Control).get_global_rect()
			if not Rect2(Vector2.ZERO, vp).grow(0.5).encloses(r) or not h.more_panel.get_global_rect().grow(0.5).encloses(r):
				bad.append("heading %s outside %s" % [k.name, str(r)])
	if heads.keys().size() != present.size():
		bad.append("headings %s for clusters %s" % [str(heads.keys()), str(present.keys())])
	for k in present:
		if not heads.has(k):
			bad.append("no heading " + str(k))
	_check(bad.is_empty(), "%s %s: the More popover has a heading per cluster, inside the viewport (%s)" % [_size_name, label, ", ".join(bad)])


## The Undo toast and the placement toolbar never overlap a control of the bar (any chip, any row), the toast stays inside the
## viewport, a popover (the Run chip's explanation, More) draws over them and the toast steps aside under it (the owner: the
## Undo floated in front of the Run chip's explanation).
func _undo_toast_check(label: String) -> void:
	var h = b.hud
	var vp: Vector2 = root.get_visible_rect().size
	var bad: Array[String] = []
	h.set_undo_toast(true, "3 units: move")
	b._place_process()
	await _frames(2)
	b._place_process()
	var t: Rect2 = h.undo_toast.get_global_rect()
	if not h.undo_toast.visible or not Rect2(Vector2.ZERO, vp).grow(0.5).encloses(t):
		bad.append("toast %s not shown inside %s" % [str(t), str(vp)])
	for c in _all_controls(h._bottom):
		if c.is_visible_in_tree() and (c is BaseButton or c is AbilityChip or c is Label) and t.grow(-0.5).intersects(c.get_global_rect()):
			bad.append("toast over %s %s" % [c.name, str(c.get_global_rect())])
	# The placement toolbar with it: both on screen, clear of each other and of the bar.
	h.set_place_bar(true)
	b._place_process()
	await _frames(2)
	b._place_process()
	var pb: Rect2 = h.place_bar.get_global_rect()
	t = h.undo_toast.get_global_rect()
	if pb.intersects(t.grow(-0.5)) or not Rect2(Vector2.ZERO, vp).grow(0.5).encloses(pb):
		bad.append("toolbar %s and toast %s" % [str(pb), str(t)])
	for c in _all_controls(h._bottom):
		if c.is_visible_in_tree() and (c is BaseButton or c is AbilityChip) and pb.grow(-0.5).intersects(c.get_global_rect()):
			bad.append("toolbar over %s" % c.name)
	h.set_place_bar(false)
	# A popover on the Run chip: above the toast and toolbar in the draw order, the toast waits under it.
	h._open_explain(h.run_button)
	await _frames(2)
	b._place_process()
	var ex: Rect2 = h.explain_panel.get_global_rect()
	if h.explain_panel.get_index() < h.undo_toast.get_index() or h.explain_panel.get_index() < h.place_bar.get_index():
		bad.append("explanation drawn under the toast")
	if h.undo_toast.visible and h.undo_toast.get_global_rect().intersects(ex):
		bad.append("toast shown over the explanation")
	h._close_explain()
	await _frames(2)
	b._place_process()
	if not h.undo_toast.visible:
		bad.append("toast did not come back after the explanation closed")
	h.set_undo_toast(false)
	_check(bad.is_empty(), "%s %s: the Undo toast and the toolbar clear of every bar control, under the popovers (%s)" % [_size_name, label, ", ".join(bad)])


func _all_controls(n: Node) -> Array:
	var out: Array = []
	for c in n.get_children():
		if c is Control:
			out.append(c)
		out.append_array(_all_controls(c))
	return out


func _click_at(h, p: Vector2) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = p
	h._input(ev)
	await _frames(1)


## Withdraw and Withdraw army ask first: a popover above the button, Withdraw emits once, Cancel / outside / Esc do not.
func _confirm_test() -> void:
	var h = b.hud
	var vp: Vector2 = root.get_visible_rect().size
	_wd = 0
	_wd_all = 0
	h.withdraw_pressed.connect(func(): _wd += 1)
	h.withdraw_all_pressed.connect(func(): _wd_all += 1)
	for case in [[h.withdraw_button, "unit"], [h.withdraw_all_button, "all"]]:
		var btn: Button = case[0]
		var cnt := func() -> int: return _wd if case[1] == "unit" else _wd_all
		var tag := "%s %s" % [_size_name, btn.name if btn.name != "" else case[1]]
		var before: int = cnt.call()
		btn.pressed.emit()
		await _frames(2)
		_check(h.confirm_panel.visible and int(cnt.call()) == before, "%s: pressing opens the confirmation and emits nothing" % tag)
		_check(_rect_in(h.confirm_panel, vp), "%s: the confirmation is inside the viewport (%s)" % [tag, str(h.confirm_panel.get_global_rect())])
		h.confirm_ok.pressed.emit()
		await _frames(1)
		_check(not h.confirm_panel.visible and int(cnt.call()) == before + 1, "%s: the Withdraw row emits once and closes" % tag)
		btn.pressed.emit()
		await _frames(2)
		h.confirm_cancel.pressed.emit()
		await _frames(1)
		_check(not h.confirm_panel.visible and int(cnt.call()) == before + 1, "%s: Cancel closes without emitting" % tag)
		btn.pressed.emit()
		await _frames(2)
		await _click_at(h, Vector2(2, 2))
		_check(not h.confirm_panel.visible and int(cnt.call()) == before + 1, "%s: a press outside closes without emitting" % tag)
		btn.pressed.emit()
		await _frames(2)
		var esc := InputEventKey.new()
		esc.keycode = KEY_ESCAPE
		esc.pressed = true
		h._input(esc)
		_check(not h.confirm_panel.visible and int(cnt.call()) == before + 1, "%s: Esc closes without emitting" % tag)
	# One popover at a time.
	h.withdraw_button.pressed.emit()
	await _frames(1)
	h.set_speed_panel_open(true)
	_check(not h.confirm_panel.visible, "%s: the speed popover closes the confirmation" % _size_name)
	h.set_speed_panel_open(false)
	h.withdraw_button.pressed.emit()
	await _frames(1)
	_check(h.confirm_panel.visible and not h.speed_panel.visible and not h.opt_panel.visible and not h.more_panel.visible, "%s: opening it closes the others" % _size_name)
	h.close_confirm()


## Why a fit failed: each control's estimated and real width.
func _dump() -> void:
	var h = b.hud
	var vp: Vector2 = root.get_visible_rect().size
	print("DUMP viewport ", vp, " bottom ", h._bottom.size, " group min ", h.group_box.get_combined_minimum_size().x, " group ",
		h.group_box.get_global_rect(), " actions ", h.actions_box.get_global_rect(), " chips_box ", h.chips_box.get_global_rect())
	for c in [h.halt_button, h.run_button, h.withdraw_button]:
		print("  ", c.name, " est ", (c.width_for(c.compact_mode) if c.has_method("width_for") else h._button_w(c, c.text)),
			" real ", c.size.x, " min ", c.get_combined_minimum_size().x, " ", c.text)
	for c in h._chip_order:
		if c.visible:
			print("  ", c.key, " est ", c.width_for(c.compact_mode), " real ", c.size.x, " min ", c.get_combined_minimum_size().x, " ", c.text, " parent ", c.get_parent().name)


func _stress() -> void:
	# Every chip applicable: the worst bar the game can show.
	var h = b.hud
	b.process_mode = Node.PROCESS_MODE_DISABLED   # (the battle refreshes the bar as it runs; hold it still)
	for c in h._chip_order:
		if (c as AbilityChip).key.begins_with("grp") and (c as AbilityChip) != h.group_plus:
			continue   # (the group chips show as the groups exist: _groups_check)
		(c as AbilityChip).visible = true
		if (c as AbilityChip).ab >= 0:
			(c as AbilityChip).set_state("Mixed")
	h._fit_actions()
	await _frames(2)


## Open a chip's options (More first when the chip is under it), pick the row with `value`; returns the popover's rect.
func _choose(c: AbilityChip, value: int) -> void:
	var h = b.hud
	if c.get_parent() == h.more_box:
		h._set_more_open(true)
		await _frames(2)
	c.pressed.emit()
	await _frames(2)
	var row = h.opt_box.find_child("opt_%d" % value, false, false)
	if row == null:
		_check(false, "%s: a row for %d" % [c.key, value])
		return
	row.pressed.emit()
	await _frames(2)


## Words of the open popover's rows.
func _row_words() -> Array:
	var out := []
	for r in b.hud.opt_box.get_children():
		out.append((r as Button).text)
	return out


## Every multi-state chip's options popover: inside the viewport, the right rows 42 px high, closes on the chip again.
func _options_stress() -> void:
	var h = b.hud
	var vp: Vector2 = root.get_visible_rect().size
	var want := {"run": ["On", "Off"], "fire": ["At will", "Hold"], "skirmish": ["On", "Off"], "stance": ["Line", "Cover", "Hold street"],
		"bounds": ["On", "Off"], "deploy": ["On", "Off"], "refill": ["On", "Off"], "forage": ["On", "Off"], "release": ["Ready", "Tap an enemy"]}
	var seen := 0
	var chips: Array = [h.run_button]
	chips.append_array(h._chip_order)
	for c in chips:
		var ch: AbilityChip = c
		if not ch.visible:
			continue
		var states: Array = []
		if ch.ab >= 0:
			states = ["Auto", "Hold"] if ch.ab == UT.AB_PISTOL else ["Auto", "Hold", "Use now"]
		elif ch.key == "ammo":
			states = ["*", "*"]
		else:
			states = want.get(ch.key, [])
		if ch.get_parent() == h.more_box:
			h._set_more_open(true)
			await _frames(2)
		ch.pressed.emit()
		await _frames(2)
		var tag := "%s %s: %s options" % [_size_name, "under More" if ch.get_parent() == h.more_box else "on the bar", ch.key]
		if states.is_empty():
			_check(not h.opt_panel.visible, tag + ": a single-action chip opens none")
			continue
		seen += 1
		var words := _row_words()
		var words_ok := words.size() == states.size()
		for i in states.size():
			if words_ok and states[i] != "*" and words[i] != states[i]:
				words_ok = false
		_check(h.opt_panel.visible and words_ok, tag + " list %s" % str(words))
		var pr: Rect2 = h.opt_panel.get_global_rect()
		_check(_rect_in(h.opt_panel, vp), tag + " stay inside the viewport %s of %s" % [str(pr), str(vp)])
		var tall := true
		for r in h.opt_box.get_children():
			if (r as Control).size.y < 41.5:
				tall = false
		_check(tall, tag + ": rows are 42 px")
		if ch.get_parent() != h.more_box:
			_check(pr.end.y <= ch.get_global_rect().position.y + 0.5, tag + ": above the chip")
		else:
			_check(h.more_panel.visible, tag + ": More stays open under it")
		ch.pressed.emit()
		await _frames(2)
		_check(not h.opt_panel.visible, tag + ": the chip again closes it")
	h._set_more_open(false)
	_check(seen >= 8, "%s: %d multi-state chips checked" % [_size_name, seen])


## Every chip's long-press explanation (the stress bar): inside the viewport, above a bar chip, the title right, a
## 'Unit book' row, one row per state of a multi-state chip, and opening the options closes it.
func _explain_stress() -> void:
	var h = b.hud
	var vp: Vector2 = root.get_visible_rect().size
	var n := 0
	for c in h._chip_order:
		var ch: AbilityChip = c
		if not ch.visible or ch.key.begins_with("grp"):
			continue
		if ch.get_parent() == h.more_box:
			h._set_more_open(true)
			await _frames(2)
		h._open_explain(ch)
		await _frames(2)
		var tag := "%s %s: %s explanation" % [_size_name, "under More" if ch.get_parent() == h.more_box else "on the bar", ch.key]
		var rows: int = h._chip_rows(ch).size()
		var n_rows := 0
		for k in h.explain_box.get_children():
			if str(k.name).begins_with("ex_row_"):
				n_rows += 1
		var ok: bool = h.explain_panel.visible and _rect_in(h.explain_panel, vp) and h.explain_box.get_node("ex_title").text == ch.tip_title \
			and h.explain_box.has_node("ex_book") and n_rows == (rows if rows > 1 else 0) and not h.opt_panel.visible
		_check(ok, tag + " (%s, %d state rows)" % [str(h.explain_panel.get_global_rect()), n_rows])
		if ch.get_parent() != h.more_box:
			var er: Rect2 = h.explain_panel.get_global_rect()
			var cr: Rect2 = ch.get_global_rect()
			_check(er.end.y <= cr.position.y + 0.5 or (h.two_rows and not er.intersects(cr.grow(-0.5))),
				tag + ": above the chip (beside it, clear of it, when the double stack leaves no room above)")
		n += 1
		h._close_explain()
	h._set_more_open(false)
	_check(n >= 10, "%s: %d explanations checked" % [_size_name, n])


## A real skirmish selection: each row sends the expected order; Esc, a selection change and the other popovers close it.
func _options_orders(by_role: Dictionary) -> void:
	var h = b.hud
	await _select_types(["skirmish"], by_role)
	var u: int = b.selection[0]
	var fire0: int = b.orders.value(u, "fire")
	for pair in [[h.fire_button, 0], [h.fire_button, 1]]:
		await _choose(pair[0], pair[1])
		_check(b.orders.value(u, "fire") == pair[1] and h.fire_button.state_word == ("at will" if pair[1] == 1 else "hold"),
			"%s: the Fire row %d sends the fire order (%s)" % [_size_name, pair[1], h.fire_button.text])
	await _choose(h.fire_button, 1)
	_check(b.orders.value(u, "fire") == 1, "%s: choosing the current Fire row changes nothing" % _size_name)
	if h.stance_button.visible:
		await _choose(h.stance_button, 2)
		_check(b.orders.value(u, "stance") == 2 and h.stance_button.state_word == "Hold", "%s: the Stance row Hold street (%s)" % [_size_name, h.stance_button.text])
		await _choose(h.stance_button, 1)
		_check(b.orders.value(u, "stance") == 1, "%s: the Stance row Cover" % _size_name)
	await _choose(h.run_button, 1)
	_check(b.orders.value(u, "run") == 1 and h.run_button.state_word == "on", "%s: the Run row On" % _size_name)
	# Closing without a change: Esc, a selection change, speed popover, More.
	var f: int = b.orders.value(u, "fire")
	await _open_chip(h.fire_button)
	_check(h.opt_panel.visible, "%s: Fire's options open" % _size_name)
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	Input.parse_input_event(esc)
	await _frames(2)
	_check(not h.opt_panel.visible and b.orders.value(u, "fire") == f, "%s: Esc closes it with no change" % _size_name)
	await _open_chip(h.fire_button)
	await _select_types(["line"], by_role)
	_check(not h.opt_panel.visible, "%s: a selection change closes it" % _size_name)
	await _select_types(["skirmish"], by_role)
	await _open_chip(h.fire_button)
	h.set_speed_panel_open(true)
	_check(not h.opt_panel.visible, "%s: opening the speed popover closes it" % _size_name)
	h.set_speed_panel_open(false)
	if h.more_button.visible:
		await _open_chip(h.fire_button)
		h._set_more_open(true)
		_check(not h.opt_panel.visible, "%s: opening More closes it" % _size_name)
		h._set_more_open(false)
	await _open_chip(h.fire_button)
	var out := Vector2(2, 2)
	var tap := InputEventScreenTouch.new()
	tap.position = out
	tap.pressed = true
	h._input(tap)
	_check(not h.opt_panel.visible and b.orders.value(u, "fire") == f, "%s: a press outside closes it with no change" % _size_name)
	_check(fire0 == 1 or fire0 == 0, "(fire order read)")


func _open_chip(c: AbilityChip) -> void:
	var h = b.hud
	if c.get_parent() == h.more_box:
		h._set_more_open(true)
		await _frames(2)
	c.pressed.emit()
	await _frames(2)


func _run() -> void:
	var by_role := _types_by_role()
	_check(by_role.size() >= 8, "a row of each role found (%d roles)" % by_role.size())
	var sc := _scenario(by_role)
	for sz in SIZES:
		_size_name = "%dx%d" % [sz[0], sz[1]]
		await _resize(sz[0], sz[1], sz[2])
		await _new_battle(sc)
		var h = b.hud
		var vp: Vector2 = root.get_visible_rect().size
		print("viewport ", vp, " window ", DisplayServer.window_get_size())
		# The capsule: glyphs on a phone, words on a desktop.
		var glyphs: bool = h._cap_tiles["line"].visible
		_check(glyphs == sz[2], "%s: the capsule shows %s" % [_size_name, "role glyphs" if sz[2] else "words"])
		_check(h.group_buttons["line"].text == ("" if sz[2] else "Line") and h.deselect_button.text == "None", "%s: segment texts" % _size_name)
		_check(h.group_buttons.keys() == ["all", "line", "skirmish", "shock", "horse", "guns"], "%s: group_buttons keep their keys" % _size_name)
		await _select_types([], by_role)
		await _fit("nothing selected", false)
		for r in by_role:
			await _select_types([r], by_role)
			await _fit("role " + str(r), not (str(r).begins_with("guns")))
		await _select_types([], by_role)
		await _fit("everything (mixed)")
		await _confirm_test()
		await _select_types([], by_role)
		await _undo_toast_check("everything (mixed)")
		await _select_types(["line", "skirmish", "guns_field"], by_role)
		await _fit("line + skirmish + guns")
		await _stress()
		await _fit("stress: every chip")
		await _undo_toast_check("stress: every chip")
		_check(h.two_rows == (sz[0] < 2000) and h.chips_up.visible == h.two_rows,
			"%s: the stress bar is double stacked exactly where one row overflows (two_rows %s)" % [_size_name, str(h.two_rows)])
		if h.two_rows:
			# The armed ability never goes under More, and the second row is paid for in bottom_height().
			var arm: AbilityChip = h.ab_chips[UT.AB_PISTOL]
			arm.set_state("Use now", true)
			h._fit_actions()
			await _frames(2)
			_check(arm.get_parent() != h.more_box, "%s: an armed ability stays on the bar with two rows" % _size_name)
			arm.set_state("Mixed", false)
			h._fit_actions()
			await _frames(2)
			_check(h.bottom_height() >= 117.0 + 36.0, "%s: bottom_height() %.0f includes the second row" % [_size_name, h.bottom_height()])
		await _options_stress()
		await _explain_stress()
		b.process_mode = Node.PROCESS_MODE_INHERIT
		await _options_orders(by_role)
		if _shots != "" and sz[2]:
			# A skirmish unit, then the mixed selection, on the phone.
			await _select_types(["skirmish"], by_role)
			await _frames(4)
			root.get_texture().get_image().save_png("%s/hud_phone_skirmish.png" % _shots)
			await _select_types([], by_role)
			await _frames(4)
			root.get_texture().get_image().save_png("%s/hud_phone_mixed.png" % _shots)
			b.hud._set_more_open(true)
			await _frames(4)
			root.get_texture().get_image().save_png("%s/hud_phone_mixed_more.png" % _shots)
			b.hud._set_more_open(false)
		await _ammo_mark_check()
		await _groups_check(by_role, sz[2])
	await _states(by_role)
	await _resize_check(by_role)
	await _siege()
	UiScale._dpr_override = -1.0
	UiScale._touch_override = -1
	print("RESULT: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	quit(0 if failures == 0 else 1)


## A unit's special arrow: its card carries the kind's glyph (and a tip saying what it does) inside the card, a plain unit's
## carries none (docs/design/ui.md "A unit's special arrow is marked").
func _ammo_mark_check() -> void:
	var ba := UT.index_of("native_bowmen")
	var units: Array = [Scenarios.unit(0, ba, UT.size_of(ba), 100, 150, 0), Scenarios.unit(0, ba, UT.size_of(ba), 130, 150, 0),
		Scenarios.unit(0, UT.index_of("archer"), 60, 160, 150, 0), Scenarios.unit(1, UT.index_of("spear"), 80, 150, 40, 512)]
	units[1]["ak"] = UT.ammo_index("poison_arrows")
	units[2]["ak"] = UT.ammo_index("fire_arrows")
	var sc := Scenarios._test(units, [])
	sc["ai_sides"] = [1]
	await _new_battle(sc)
	var h = b.hud
	var mine: Array[int] = []
	for u in b.sim.n_units:
		if b.sim.u_side[u] == 0:
			mine.append(u)
	b.sim.u_akind[mine[1]] = 1   # (shooting its special kind: lit)
	await _pick(mine)
	h.update_cards(b.sim)   # (the cards refresh on a 0.25 s timer, not per frame: refresh them now)
	await _frames(3)
	var bad: Array[String] = []
	var want := [-1, UT.ammo_index("poison_arrows"), UT.ammo_index("fire_arrows")]
	for k in 3:
		var f = h._faces[mine[k]]
		if f.ak != want[k]:
			bad.append("card %d ak %d, want %d" % [k, f.ak, want[k]])
		if k == 0:
			if f.ak_rc.size != Vector2.ZERO:
				bad.append("a plain unit's card has a mark")
			continue
		var inside: bool = Rect2(Vector2.ZERO, f.size).grow(0.5).encloses(f.ak_rc) and f.ak_rc.size.x > 0.0
		if not inside:
			bad.append("card %d mark %s outside the card %s" % [k, str(f.ak_rc), str(f.size)])
	_check(f_ok(bad), "%s: a special arrow's card carries its glyph inside the card, a plain unit's none (%s)" % [_size_name, ", ".join(bad)])
	_check(h._faces[mine[1]].ak_use == 1 and h._faces[mine[2]].ak_use == 0, "%s: the glyph is lit for the kind shot now, held back otherwise" % _size_name)
	_check(Traits.ammo_icon(want[1]) != "" and Kit.UiIcons.has(Traits.ammo_icon(want[1])) and Kit.UiIcons.has(Traits.ammo_icon(want[2])),
		"%s: both kinds have a drawn icon" % _size_name)


## Control groups (docs/design/ui.md "Control groups"): the Groups cluster with 0, 3 and 9 groups fits at every size (chips on
## the bar xor under More, none clipped, the "+" chip only while a selection exists and fewer than nine groups do), the
## badges stay inside the cards, the Undo toast still clears the chips, and with nothing selected the chips are still
## there to select a group by.
func _groups_check(by_role: Dictionary, sz_phone: bool) -> void:
	await _new_battle(_scenario(by_role))
	var h = b.hud
	var vp: Vector2 = root.get_visible_rect().size
	var mine: Array[int] = []
	for u in b.sim.n_units:
		if b.sim.u_side[u] == 0:
			mine.append(u)
	_check(mine.size() >= 4, "%s: the groups scenario has units (%d)" % [_size_name, mine.size()])
	for k in [0, 3, 9]:
		b.control_groups.clear()
		await _pick(mine)
		for n in range(1, k + 1):
			var one: Array[int] = [mine[(n - 1) % mine.size()], mine[n % mine.size()]]
			await _pick(one)
			b._group_assign(n, "set")
		await _pick(mine)
		await _frames(3)
		h.update_cards(b.sim)
		var tag := "%s with %d groups" % [_size_name, k]
		var bad: Array[String] = []
		for n in range(1, 10):
			var c: AbilityChip = h.group_chips[n]
			if c.visible != (n <= k):
				bad.append("chip %d visible %s" % [n, str(c.visible)])
			if c.visible:
				var in_bar: bool = c.get_parent() == h.chips_box or c.get_parent() == h.chips_up
				if in_bar and not _rect_in(c, vp):
					bad.append("chip %d off screen %s" % [n, str(c.get_global_rect())])
				if not in_bar and c.get_parent() != h.more_box:
					bad.append("chip %d nowhere" % n)
		_check(h.group_plus.visible == (k < 9 and sz_phone), tag + ": the + chip shows on touch / narrow screens while fewer than nine groups exist")
		if h.group_plus.visible and h.group_plus.get_parent() != h.more_box and not _rect_in(h.group_plus, vp):
			bad.append("+ off screen")
		_check(bad.is_empty(), tag + ": group chips on the bar or under More, none clipped (%s)" % ", ".join(bad))
		await _fit(tag)
		# The badges: a unit in a group has its numbers on its card, inside it.
		var font := ThemeDB.fallback_font
		var badge_bad: Array[String] = []
		for u in mine:
			var f = h._faces[u]
			var want: String = h.card_group_text(u)
			if f.group_text != want:
				badge_bad.append("card %d says '%s', want '%s'" % [u, f.group_text, want])
			if want != "":
				var w := font.get_string_size(want, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x + 5.0
				if w > f.size.x - 8.0:
					badge_bad.append("badge %d wide %.0f in card %.0f" % [u, w, f.size.x])
		_check(badge_bad.is_empty(), tag + ": the badges are on the cards and inside them (%s)" % ", ".join(badge_bad))
		await _undo_toast_check(tag)
		# Nothing selected: the group chips remain (to select a group), Halt and Withdraw go.
		await _pick([] as Array[int])
		await _frames(2)
		if k > 0:
			var empty_bad: Array[String] = []
			if not h.actions_box.is_visible_in_tree():
				empty_bad.append("the chip row is hidden")
			if h.group_plus.visible:
				empty_bad.append("+ with no selection")
			if h.halt_button.visible or h.withdraw_button.visible or h.run_button.visible:
				empty_bad.append("Halt / Run / Withdraw with no selection")
			for n in range(1, k + 1):
				var c: AbilityChip = h.group_chips[n]
				if c.get_parent() != h.more_box and not (c.is_visible_in_tree() and _rect_in(c, vp)):
					empty_bad.append("chip %d not on screen" % n)
			_check(empty_bad.is_empty(), tag + ": with nothing selected the group chips are still on the bar (%s)" % ", ".join(empty_bad))
		else:
			_check(not h.actions_box.visible, tag + ": no groups and nothing selected: no chip row")
	b.control_groups.clear()


func f_ok(bad: Array[String]) -> bool:
	return bad.is_empty()


## The chips' states: a cycle, Mixed, Pistols' two states, the armed text, the card strip.
func _states(by_role: Dictionary) -> void:
	_size_name = "states"
	await _resize(1280, 720, false)
	await _new_battle(_scenario(by_role))
	var h = b.hud
	var gren := -1
	var pist := -1
	var car := -1
	for u in b.sim.n_units:
		if b.sim.u_side[u] != 0:
			continue
		var m: int = b.sim.t_abil[b.sim.u_type[u]]
		if gren < 0 and (m & (1 << UT.AB_GRENADE)) != 0:
			gren = u
		if pist < 0 and (m & (1 << UT.AB_PISTOL)) != 0:
			pist = u
		if car < 0 and (m & (1 << UT.AB_CARACOLE)) != 0:
			car = u
	_check(gren >= 0 and pist >= 0 and car >= 0, "units with grenades (%d), pistols (%d) and the caracole (%d) are in the field" % [gren, pist, car])
	await _pick([gren])
	var gc: AbilityChip = h.ab_chips[UT.AB_GRENADE]
	_check(gc.visible and gc.state_word == "Auto" and gc.text == "Grenades: Auto", "Grenades shows Auto (%s)" % gc.text)
	_check(not h.ab_chips[UT.AB_CARACOLE].visible or (b.sim.t_abil[b.sim.u_type[gren]] & (1 << UT.AB_CARACOLE)) != 0, "no Caracole chip for a unit without it")
	await _choose(gc, UT.AB_HOLD)
	_check(gc.state_word == "Hold" and gc.text == "Grenades: Hold", "the Hold row: Hold (%s)" % gc.text)
	var strip: Array = b._card_states(gren)
	_check(str(strip).contains("grenade!"), "the card strip shows the grenade on Hold (%s)" % str(strip))
	b._set_paused(false)
	await _frames(12)
	b._set_paused(true)
	_check(b.sim.ability_state(gren, UT.AB_GRENADE) == UT.AB_HOLD, "the sim got the Hold order")
	await _choose(gc, UT.AB_NOW)
	_check(b.ability_armed == UT.AB_GRENADE and gc.armed and gc.text == gc.text_for(gc.compact_mode) and gc.text in ["Use now: tap a target", "Tap a target"], "the Use now row arms the pick (%s)" % gc.text)
	_check(not b.overlay.target_lit.is_empty(), "the enemy units are lit for the pick")
	gc.pressed.emit()
	await _frames(2)
	_check(b.ability_armed < 0 and gc.state_word == "Auto" and b.overlay.target_lit.is_empty(), "the chip again cancels back to Auto (%s)" % gc.text)
	# Pistols: Auto <-> Hold only.
	await _pick([pist])
	var pc: AbilityChip = h.ab_chips[UT.AB_PISTOL]
	await _choose(pc, UT.AB_HOLD)
	_check(pc.state_word == "Hold", "Pistols: the Hold row")
	await _choose(pc, UT.AB_AUTO)
	_check(pc.state_word == "Auto" and b.ability_armed < 0, "Pistols: the Auto row")
	pc.pressed.emit()
	await _frames(2)
	_check(h.opt_panel.visible and h.opt_box.get_child_count() == 2 and h.opt_box.find_child("opt_2", false, false) == null, "Pistols' options: Auto and Hold only, no Use now")
	h._close_options()
	# Mixed states read Mixed.
	await _pick([gren, pist])
	b._ability_pressed(UT.AB_GRENADE)
	b._ability_pressed(UT.AB_PISTOL)
	await _frames(2)
	_check(not h.ab_chips[UT.AB_GRENADE].common and h.ab_chips[UT.AB_GRENADE].modulate.a < 1.0, "a chip not every selected unit has is dimmed")
	# Cards at their defaults are quiet: the strip of a fresh unit is empty.
	var quiet := true
	for u in b.sim.n_units:
		if b.sim.u_side[u] == 0 and u != gren and u != pist and not b._card_states(u).is_empty():
			quiet = false
	_check(quiet, "cards at their defaults show no state glyph")


func _resize_check(by_role: Dictionary) -> void:
	_size_name = "resize"
	await _resize(1280, 720, false)
	await _new_battle(_scenario(by_role))
	await _select_types([], by_role)
	await _fit("before the resize")
	await _resize(844, 390, true)
	await _frames(3)
	_check(b.hud._cap_tiles["line"].visible, "resized to a phone: the capsule shows glyphs")
	await _fit("after the resize to 844x390")
	await _resize(1280, 720, false)
	await _frames(3)
	_check(not b.hud._cap_tiles["line"].visible and b.hud.group_buttons["line"].text == "Line", "resized back: words")
	await _fit("after the resize back")


## A siege field: the Target chip (batter) shows for the attackers' siege guns and arms a pick of buildings.
func _siege() -> void:
	_size_name = "siege"
	await _resize(1280, 720, false)
	var ssc := Scenarios.siege_test(303, 2, 2, MapGen.PAL_ARID, Terrain.K_FLAT, 0)
	ssc["ai_sides"] = [0]   # (the player takes the attackers, side 1)
	await _new_battle(ssc, 1)
	var h = b.hud
	var g := -1
	for u in b.sim.n_units:
		if b.sim.u_side[u] == b.player_side and UT.abilities(b.sim.u_type[u]) & (1 << UT.AB_BATTER) != 0 and b.sim.t_fixed[b.sim.u_type[u]] == 0:
			g = u
			break
	_check(g >= 0, "the siege field has a siege gun on the player's side")
	if g < 0:
		return
	await _pick([g])
	var tc: AbilityChip = h.ab_chips[UT.AB_BATTER]
	_check(tc.visible and tc.label_name == "Target", "the Target chip shows for a siege gun")
	var deploying: bool = b.sim.phase != BattleSim.PHASE_BATTLE
	await _choose(tc, UT.AB_HOLD)
	await _choose(tc, UT.AB_NOW)
	await _frames(2)
	if deploying:
		_check(b.ability_armed < 0 and tc.state_word == "Auto", "in the deployment Use now is not offered: Auto -> Hold -> Auto (%s)" % tc.text)
		b.sim.phase = BattleSim.PHASE_BATTLE   # (a view test: go on as in the battle)
		await _choose(tc, UT.AB_HOLD)
		await _choose(tc, UT.AB_NOW)
		await _frames(2)
	_check(b.ability_armed == UT.AB_BATTER and b.overlay.occ_mode and b.overlay.occ_lit.size() == b.sim.ob_state.size(), "Use now lights the standing buildings (%d of %d)" % [b.overlay.occ_lit.size(), b.sim.ob_state.size()])
	b._ability_cancel(true)
	await _frames(2)
	_check(b.ability_armed < 0 and not b.overlay.occ_mode, "cancel clears the pick")
	var all_mine: Array[int] = []
	for u in b.sim.n_units:
		if b.sim.u_side[u] == b.player_side:
			all_mine.append(u)
	await _pick(all_mine)
	await _fit("siege: everything")
