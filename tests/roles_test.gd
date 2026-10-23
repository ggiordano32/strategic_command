extends SceneTree
## Roles, step 1 (docs/design/battle_sim.md "Roles and abilities"): every unit row of both packs has a
## role in UT.ROLES with a name, short name, glyph, colour, two-line "plays as" and a filter group;
## UT.filter_group lands every row in one of the selection bar's groups. Prints the roster by role.
##   godot --headless --script res://tests/roles_test.gd

const UT := preload("res://sim/unit_types.gd")
const RoleBadge := preload("res://game/role_badge.gd")

var fails := 0


func _check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("FAIL: ", what)


func _init() -> void:
	var glyphs := ["line", "scatter", "bow", "blade", "horse", "horse_dot", "gun", "gun_big", "flag", "beast"]
	_check(UT.ROLES.size() == 10 and UT.ROLE_ORDER.size() == 10, "ten roles")
	for rk in UT.ROLE_ORDER:
		var r: Dictionary = UT.ROLES.get(rk, {})
		_check(not r.is_empty(), "role %s in the table" % rk)
		for f in ["name", "short", "glyph", "colour", "plays", "group"]:
			_check(r.has(f) and str(r[f]) != "", "role %s has %s" % [rk, f])
		_check(str(r.get("glyph", "")) in glyphs, "role %s glyph drawable" % rk)
		_check(str(r.get("colour", "")).is_valid_html_color(), "role %s colour" % rk)
		_check(str(r.get("plays", "")).count("\n") == 1, "role %s plays as: two lines" % rk)
		_check(UT.FILTER_GROUPS.has(str(r.get("group", ""))), "role %s group is a filter group" % rk)
	var by: Dictionary = {}
	for ty in UT.count():
		var rk := UT.role(ty)
		_check(UT.ROLES.has(rk), "row %s (%d) has a role (%s)" % [UT.key_of(ty), ty, rk])
		_check(UT.FILTER_GROUPS.has(UT.filter_group(ty)), "row %s has a filter group" % UT.key_of(ty))
		var k := "%s|%s" % [UT.pack_of(ty), rk]
		if not by.has(k):
			by[k] = []
		(by[k] as Array).append(UT.key_of(ty))
	for pack in ["rome", "west"]:
		print("== %s" % pack)
		for rk in UT.ROLE_ORDER:
			var l: Array = by.get("%s|%s" % [pack, rk], [])
			if not l.is_empty():
				print("  %-15s %-8s %s" % [rk, "(" + UT.ROLES[rk]["group"] + ")", ", ".join(PackedStringArray(l))])
	# The few judgement calls, pinned.
	_check(UT.role(UT.index_of("war_dogs")) == "shock" and UT.role(UT.index_of("camel")) == "beast"
		and UT.role(UT.index_of("camel_archer")) == "horse_skirmish" and UT.role(UT.index_of("fort_gun")) == "guns_field"
		and UT.role(UT.index_of("mortar")) == "guns_siege" and UT.role(UT.index_of("bodyguard")) == "horse_shock", "judgement calls")
	_check(UT.filter_group(UT.index_of("general")) == "horse" and UT.filter_group(UT.index_of("hero_foot")) == "line"
		and UT.filter_group(UT.index_of("elephant")) == "horse" and UT.filter_group(UT.index_of("archer")) == "skirmish", "filter groups")
	print("RESULT: %s" % ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	quit(0 if fails == 0 else 1)
