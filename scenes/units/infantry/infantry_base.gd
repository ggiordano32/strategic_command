class_name InfantryBase
extends CharacterBody2D

signal health_changed(current, maximum)
signal unit_died

# Unit stats
@export var unit_name: String = "Infantry"
@export var max_health: float = 100.0
@export var movement_speed: float = 150.0
@export var attack_damage: float = 10.0
@export var attack_range: float = 150.0
@export var attack_cooldown: float = 1.0
@export var cover_bonus: float = 0.3  # 30% damage reduction in cover

# Unit state
var current_health: float = max_health
var target_position: Vector2 = Vector2.ZERO
var is_moving: bool = false
var is_in_cover: bool = false
var cover_direction: Vector2 = Vector2.ZERO
var cover_level: float = 0.0  # 0 = no cover, 1 = full cover
var is_selected: bool = false
var current_stance: String = "aggressive"  # aggressive, defensive, hold

# References
var current_squad: Squad = null
var current_animation: String = "idle"

# Pathfinding
var nav_agent: NavigationAgent2D
var path: Array = []
var path_index: int = 0

# Network
@export var network_id: int = 0
var is_networked: bool = false

# Components
@onready var selection_indicator = $SelectionIndicator
@onready var sprite = $Sprite2D
@onready var animation_player = $AnimationPlayer
@onready var collision_shape = $CollisionShape2D
@onready var health_bar = $HealthBar

func _ready():
	# Setup navigation
	nav_agent = $NavigationAgent2D
	nav_agent.path_desired_distance = 5.0
	nav_agent.target_desired_distance = 5.0
	
	# Initialize health
	current_health = max_health
	
	# Initialize selection state
	selection_indicator.visible = false
	
	# Only process on the network owner or in single player
	set_physics_process(not is_networked or is_network_owner())

func _physics_process(delta):
	if is_moving:
		_handle_movement(delta)
	
	_update_animation()

func _handle_movement(delta):
	if nav_agent.is_navigation_finished():
		is_moving = false
		return
	
	var next_position = nav_agent.get_next_path_position()
	var direction = global_position.direction_to(next_position)
	
	# Handle cover differently - slow down and rotate properly when in cover
	if is_in_cover:
		var cover_influence = 0.5  # Slow down in cover
		velocity = direction * movement_speed * cover_influence
	else:
		velocity = direction * movement_speed
	
	# Handle sprite orientation (flip based on movement direction)
	if direction.x != 0:
		sprite.flip_h = direction.x < 0
	
	move_and_slide()
	
	# Sync position if we're the network owner
	if is_networked and multiplayer.get_unique_id() == network_id:
		rpc("network_update_position", global_position, sprite.flip_h)

# Command the unit to move to a position
func move_to(target: Vector2):
	target_position = target
	nav_agent.target_position = target
	is_moving = true
	
	# If we're networked and the owner, send the movement command
	if is_networked and multiplayer.get_unique_id() == network_id:
		rpc("network_move_to", target)

# Apply damage to the unit
func take_damage(amount: float, attacker = null):
	var actual_damage = amount
	
	# Apply cover bonus if in cover
	if is_in_cover:
		actual_damage *= (1.0 - (cover_bonus * cover_level))
	
	current_health -= actual_damage
	current_health = max(current_health, 0)
	
	emit_signal("health_changed", current_health, max_health)
	
	# Update health bar
	health_bar.value = (current_health / max_health) * 100
	
	# Check for death
	if current_health <= 0:
		die()
	
	# If networked and we're the owner, sync the health
	if is_networked and multiplayer.get_unique_id() == network_id:
		rpc("network_update_health", current_health)

# Kill the unit
func die():
	emit_signal("unit_died")
	
	# Remove from squad if part of one
	if current_squad:
		current_squad.remove_unit(self)
	
	# Play death animation then queue free
	_play_animation("death")
	# Wait for animation to finish - in a real implementation
	# you'd connect to the animation_finished signal
	await get_tree().create_timer(1.0).timeout
	queue_free()

# Set the unit as selected or not
func set_selected(selected: bool):
	is_selected = selected
	selection_indicator.visible = selected

# Assign the unit to a squad
func set_squad(squad: Squad):
	current_squad = squad

# Apply cover data to this unit
func apply_cover(cover_data: Dictionary):
	is_in_cover = cover_data.in_cover
	cover_level = cover_data.level
	cover_direction = cover_data.direction
	
	# Visual feedback for being in cover
	if is_in_cover:
		modulate = Color(0.8, 0.8, 1.0)  # Slight blue tint when in cover
	else:
		modulate = Color(1.0, 1.0, 1.0)

# Update the current animation based on state
func _update_animation():
	var new_animation = "idle"
	
	if is_moving:
		new_animation = "run"
	elif is_in_cover:
		new_animation = "cover"
	
	if new_animation != current_animation:
		_play_animation(new_animation)

# Play an animation
func _play_animation(anim_name: String):
	if animation_player.has_animation(anim_name):
		animation_player.play(anim_name)
		current_animation = anim_name

# Networked functions
@rpc("any_peer", "call_local", "reliable")
func network_move_to(target: Vector2):
	# Only process if coming from the owner
	if multiplayer.get_remote_sender_id() == network_id:
		move_to(target)

@rpc("any_peer", "call_local", "unreliable")
func network_update_position(pos: Vector2, flip: bool):
	# Only process if coming from the owner
	if multiplayer.get_remote_sender_id() == network_id:
		global_position = pos
		sprite.flip_h = flip

@rpc("any_peer", "call_local", "reliable")
func network_update_health(health: float):
	# Only process if coming from the owner
	if multiplayer.get_remote_sender_id() == network_id:
		current_health = health
		health_bar.value = (current_health / max_health) * 100
