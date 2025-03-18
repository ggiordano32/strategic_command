class_name CoverObject
extends StaticBody2D

# Cover properties
@export var cover_strength: float = 1.0  # 0.0 to 1.0 (no cover to full cover)
@export var destructible: bool = false
@export var health: float = 100.0

# Current state
var current_health: float = 100.0
var is_destroyed: bool = false

# References
@onready var collision_shape = $CollisionShape2D
@onready var sprite = $Sprite2D

func _ready():
	# Initialize health
	current_health = health
	
	# Register with the cover system
	var cover_system = get_node("/root/Game/Systems/CoverSystem")
	if cover_system:
		cover_system.register_cover_object(self)

func _exit_tree():
	# Unregister from cover system when removed
	var cover_system = get_node("/root/Game/Systems/CoverSystem")
	if cover_system:
		cover_system.unregister_cover_object(self)

# Take damage if destructible
func take_damage(amount: float):
	if not destructible:
		return
		
	current_health -= amount
	current_health = max(current_health, 0)
	
	# Update visual representation
	var health_percent = current_health / health
	sprite.modulate = Color(1.0, health_percent, health_percent)
	
	# Destroy if health depleted
	if current_health <= 0 and not is_destroyed:
		destroy()

# Destroy the cover object
func destroy():
	is_destroyed = true
	
	# Play destruction animation/effect
	# Assuming we have a simple animation here
	sprite.modulate = Color(0.3, 0.3, 0.3, 0.5)
	
	# Disable collision
	collision_shape.disabled = true
	
	# Unregister from cover system
	var cover_system = get_node("/root/Game/Systems/CoverSystem")
	if cover_system:
		cover_system.unregister_cover_object(self)
	
	# In a real game, you might want to replace this with a destroyed version
	# or play a destruction animation before freeing
