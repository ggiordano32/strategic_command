class_name FactionData
extends Resource

# Basic faction information
@export var faction_id: String
@export var faction_name: String
@export var faction_description: String
@export var faction_color: Color = Color(1.0, 1.0, 1.0)
@export var faction_icon: Texture2D

# Unit types available to this faction (dictionary of unit IDs to scene paths)
@export var available_units: Dictionary = {}

# Faction-specific bonuses and modifiers
@export var movement_speed_modifier: float = 1.0
@export var attack_damage_modifier: float = 1.0
@export var health_modifier: float = 1.0
@export var build_speed_modifier: float = 1.0
@export var resource_gathering_modifier: float = 1.0

# Starting units and resources
@export var starting_units: Array[String] = []
@export var starting_resources: int = 1000

# Get a unit scene by ID
func get_unit_scene(unit_id: String) -> String:
	if available_units.has(unit_id):
		return available_units[unit_id]
	return ""

# Check if a unit type is available to this faction
func has_unit(unit_id: String) -> bool:
	return available_units.has(unit_id)
