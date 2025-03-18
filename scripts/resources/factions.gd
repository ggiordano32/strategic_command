# This script will create and register the faction data
# It should be included in an autoload script or initialized at game start

# Create Coalition faction
var coalition_faction = FactionData.new()
coalition_faction.faction_id = "coalition"
coalition_faction.faction_name = "The Coalition"
coalition_faction.faction_description = "Western-inspired forces focusing on mobility, technology, and adaptability."
coalition_faction.faction_color = Color(0.0, 0.5, 1.0)  # Blue
coalition_faction.available_units = {
	"rifle_infantry": "res://scenes/units/infantry/coalition/rifle_infantry.tscn",
	"engineer": "res://scenes/units/infantry/coalition/engineer_infantry.tscn",
	"sniper": "res://scenes/units/infantry/coalition/sniper_infantry.tscn"
}
coalition_faction.movement_speed_modifier = 1.1  # 10% faster movement
coalition_faction.attack_damage_modifier = 1.0
coalition_faction.health_modifier = 0.9  # 10% less health
coalition_faction.build_speed_modifier = 1.0
coalition_faction.resource_gathering_modifier = 1.0
coalition_faction.starting_units = ["rifle_infantry", "rifle_infantry", "engineer"]
coalition_faction.starting_resources = 1000

# Create Collective faction
var collective_faction = FactionData.new()
collective_faction.faction_id = "collective"
collective_faction.faction_name = "The Collective"
collective_faction.faction_description = "Eastern-inspired forces emphasizing strength in numbers, industrial efficiency, and defensive power."
collective_faction.faction_color = Color(1.0, 0.2, 0.2)  # Red
collective_faction.available_units = {
	"conscript": "res://scenes/units/infantry/collective/conscript_infantry.tscn",
	"technician": "res://scenes/units/infantry/collective/technician_infantry.tscn",
	"heavy_gunner": "res://scenes/units/infantry/collective/heavy_gunner_infantry.tscn"
}
collective_faction.movement_speed_modifier = 0.9  # 10% slower movement
collective_faction.attack_damage_modifier = 1.0
collective_faction.health_modifier = 1.2  # 20% more health
collective_faction.build_speed_modifier = 1.1  # 10% faster building
collective_faction.resource_gathering_modifier = 1.1  # 10% more resources
collective_faction.starting_units = ["conscript", "conscript", "conscript", "technician"]
collective_faction.starting_resources = 1000

# Register factions in a global registry
var registered_factions = {
	"coalition": coalition_faction,
	"collective": collective_faction
}

# Function to get a faction by ID
func get_faction(faction_id: String) -> FactionData:
	if registered_factions.has(faction_id):
		return registered_factions[faction_id]
	return null
