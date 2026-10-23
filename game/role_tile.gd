extends Control
## A small Control showing a role badge (game/role_badge.gd); its tooltip is the role's "plays as".
## View only.

const UT := preload("res://sim/unit_types.gd")
const RoleBadge := preload("res://game/role_badge.gd")
const Kit := preload("res://game/campaign/ui_kit.gd")

var role := ""


func _init(r: String = "", px: float = 22.0) -> void:
	custom_minimum_size = Vector2(px, px)
	mouse_filter = Control.MOUSE_FILTER_PASS
	set_role(r)


func set_role(r: String) -> void:
	role = r
	visible = r != ""
	if r != "" and UT.ROLES.has(r):
		Kit.tip(self, str(UT.ROLES[r]["name"]), RoleBadge.plays(r))
	queue_redraw()


func _draw() -> void:
	RoleBadge.draw_badge(self, role, Rect2(Vector2.ZERO, size))
