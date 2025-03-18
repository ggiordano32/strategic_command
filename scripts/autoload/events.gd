extends Node

# Game flow signals
signal game_started
signal game_paused
signal game_resumed
signal game_over(winner)

# Selection signals
signal unit_selected(unit)
signal unit_deselected(unit)
signal squad_selected(squad)
signal squad_deselected(squad)
signal multiple_units_selected(units)
signal selection_cleared

# Action signals
signal move_command_issued(position)
signal attack_command_issued(target)
signal hold_position_command_issued
signal use_ability_command_issued(ability_id)

# Building/Production signals
signal building_placed(building, position)
signal unit_production_started(unit_type, production_time)
signal unit_production_completed(unit)

# Resource signals
signal resource_point_captured(point, owner)
signal resources_updated(resources)

# Team/faction signals
signal team_defeated(team_id)

# Network signals
signal player_connected(id)
signal player_disconnected(id)
signal host_migration_started
signal host_migration_completed(new_host_id)

# Active squads and units
var active_squads: Array = []
var selected_units: Array = []
var selected_squads: Array = []

# Register a squad
func register_squad(squad):
	if not active_squads.has(squad):
		active_squads.append(squad)
		squad.connect("squad_selected", _on_squad_selected.bind(squad))
		squad.connect("squad_deselected", _on_squad_deselected.bind(squad))

# Unregister a squad
func unregister_squad(squad):
	var idx = active_squads.find(squad)
	if idx != -1:
		active_squads.remove_at(idx)
	
	# Also remove from selection if selected
	_remove_from_selection(squad)

# Register a unit
func register_unit(unit):
	unit.connect("unit_selected", _on_unit_selected.bind(unit))
	unit.connect("unit_deselected", _on_unit_deselected.bind(unit))

# Issue a move command to all selected units/squads
func issue_move_command(position: Vector2):
	for squad in selected_squads:
		squad.move_to(position)
	
	for unit in selected_units:
		if not unit.current_squad or not selected_squads.has(unit.current_squad):
			unit.move_to(position)
	
	emit_signal("move_command_issued", position)

# Clear the current selection
func clear_selection():
	for squad in selected_squads:
		squad.deselect()
	
	for unit in selected_units:
		unit.set_selected(false)
	
	selected_squads.clear()
	selected_units.clear()
	
	emit_signal("selection_cleared")

# Handle squad selection
func _on_squad_selected(squad):
	if not selected_squads.has(squad):
		selected_squads.append(squad)
		emit_signal("squad_selected", squad)

# Handle squad deselection
func _on_squad_deselected(squad):
	_remove_from_selection(squad)

# Handle unit selection
func _on_unit_selected(unit):
	if not selected_units.has(unit):
		selected_units.append(unit)
		emit_signal("unit_selected", unit)

# Handle unit deselection
func _on_unit_deselected(unit):
	var idx = selected_units.find(unit)
	if idx != -1:
		selected_units.remove_at(idx)
		emit_signal("unit_deselected", unit)

# Remove a squad from selection
func _remove_from_selection(squad):
	var idx = selected_squads.find(squad)
	if idx != -1:
		selected_squads.remove_at(idx)
		emit_signal("squad_deselected", squad)
