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

const SIZES := [[844, 390, true], [1180, 820, false], [1280, 720, false]]

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
		var in_bar: bool = ch.get_parent() == h.chips_box
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
	if under > 0 and not h.more_button.visible:
		bad.append("chips under More but no More")
	if under == 0 and h.more_button.visible:
		bad.append("More with nothing under it")
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
		h._set_more_open(false)
		await _frames(1)


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
		(c as AbilityChip).visible = true
		if (c as AbilityChip).ab >= 0:
			(c as AbilityChip).set_state("Mixed")
	h._fit_actions()
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
		await _select_types(["line", "skirmish", "guns_field"], by_role)
		await _fit("line + skirmish + guns")
		await _stress()
		await _fit("stress: every chip")
		b.process_mode = Node.PROCESS_MODE_INHERIT
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
	await _states(by_role)
	await _resize_check(by_role)
	await _siege()
	UiScale._dpr_override = -1.0
	UiScale._touch_override = -1
	print("RESULT: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	quit(0 if failures == 0 else 1)


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
	gc.pressed.emit()
	await _frames(2)
	_check(gc.state_word == "Hold" and gc.text == "Grenades: Hold", "a tap: Hold (%s)" % gc.text)
	var strip: Array = b._card_states(gren)
	_check(str(strip).contains("grenade!"), "the card strip shows the grenade on Hold (%s)" % str(strip))
	b._set_paused(false)
	await _frames(12)
	b._set_paused(true)
	_check(b.sim.ability_state(gren, UT.AB_GRENADE) == UT.AB_HOLD, "the sim got the Hold order")
	gc.pressed.emit()
	await _frames(2)
	_check(b.ability_armed == UT.AB_GRENADE and gc.armed and gc.text == "Use now: tap a target", "a second tap arms Use now (%s)" % gc.text)
	_check(not b.overlay.target_lit.is_empty(), "the enemy units are lit for the pick")
	gc.pressed.emit()
	await _frames(2)
	_check(b.ability_armed < 0 and gc.state_word == "Auto" and b.overlay.target_lit.is_empty(), "the chip again cancels back to Auto (%s)" % gc.text)
	# Pistols: Auto <-> Hold only.
	await _pick([pist])
	var pc: AbilityChip = h.ab_chips[UT.AB_PISTOL]
	pc.pressed.emit()
	await _frames(2)
	_check(pc.state_word == "Hold", "Pistols: Auto -> Hold")
	pc.pressed.emit()
	await _frames(2)
	_check(pc.state_word == "Auto" and b.ability_armed < 0, "Pistols: Hold -> Auto (no Use now)")
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
	tc.pressed.emit()
	tc.pressed.emit()
	await _frames(2)
	if deploying:
		_check(b.ability_armed < 0 and tc.state_word == "Auto", "in the deployment Use now is not offered: Auto -> Hold -> Auto (%s)" % tc.text)
		b.sim.phase = BattleSim.PHASE_BATTLE   # (a view test: go on as in the battle)
		tc.pressed.emit()
		tc.pressed.emit()
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
