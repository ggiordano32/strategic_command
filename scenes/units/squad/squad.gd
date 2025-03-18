class_name Squad
extends Node2D

signal squad_selected
signal squad_deselected
signal squad_moved(position)

# Squad properties
@export var squad_name: String = "Squad"
@export var max_units: int = 5
@export var formation_spacing: float = 40.0
@export var faction: String = "coalition"

# Squad state
var is_selected: bool = false
var target_position: Vector2 = Vector2.ZERO
var units: Array[InfantryBase] = []
var formation_positions: Array[Vector2] = []

# Network properties
@export var network_id: int = 0  # Set by the multiplayer system
var is_networked: bool = false
var sync_positions: bool = true

# References
var cover_system: CoverSystem

func _ready():
	# Only process on the network owner or in single player
	set_process(not is_networked or multiplayer.get_unique_id() == network_id)
	
	# Connect to global events system
	if Engine.has_singleton("Events"):
		var events = get_node("/root/Events")
		events.register_squad(self)
	
	# Generate initial formation positions
	_update_formation_positions()

func _process(delta):
	if units.size() > 0:
		_update_formation_positions()
		_move_units_to_formation(delta)

func _update_formation_positions():
	formation_positions.clear()
	
	# Create a simple line formation for now
	# Can be expanded with different formation types later
	var offset = Vector2.ZERO
	for i in range(max_units):
		if i % 2 == 0:
			offset.x = (i / 2) * formation_spacing
		else:
			offset.x = -((i + 1) / 2) * formation_spacing
			
		formation_positions.append(offset)

func _move_units_to_formation(delta):
	for i in range(units.size()):
		if i < formation_positions.size():
			var target = position + formation_positions[i]
			units[i].move_to(target)

# Add unit to the squad
func add_unit(unit: InfantryBase) -> bool:
	if units.size() >= max_units:
		return false
		
	units.append(unit)
	unit.set_squad(self)
	return true

# Remove unit from the squad
func remove_unit(unit: InfantryBase) -> bool:
	var idx = units.find(unit)
	if idx != -1:
		units.remove_at(idx)
		unit.set_squad(null)
		return true
	return false

# Command the squad to move to a position
func move_to(target: Vector2):
	target_position = target
	position = target
	
	# If networked, sync this command
	if is_networked:
		rpc("network_move_to", target)
		
	emit_signal("squad_moved", target)

# Select this squad
func select():
	if not is_selected:
		is_selected = true
		_update_selection_visual(true)
		emit_signal("squad_selected")

# Deselect this squad
func deselect():
	if is_selected:
		is_selected = false
		_update_selection_visual(false)
		emit_signal("squad_deselected")

# Update visual feedback for selection state
func _update_selection_visual(selected: bool):
	for unit in units:
		unit.set_selected(selected)

# Check if squad is in cover
func check_cover():
	if cover_system:
		for unit in units:
			var cover_data = cover_system.evaluate_cover(unit.global_position)
			unit.apply_cover(cover_data)

# Networked functions
@rpc("any_peer", "call_local", "reliable")
func network_move_to(target: Vector2):
	# Only process if coming from the owner
	if multiplayer.get_remote_sender_id() == network_id:
		position = target
