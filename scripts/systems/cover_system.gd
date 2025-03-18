class_name CoverSystem
extends Node

# System properties
@export var cover_check_radius: float = 50.0
@export var cover_raycast_distance: float = 100.0
@export var cover_raycast_count: int = 8

# Cover objects in the game
var cover_objects: Array = []

# The physics space state for raycasting
var space_state: PhysicsDirectSpaceState2D

func _ready():
	# We'll need to wait until we're in the scene tree to get the space state
	await get_tree().process_frame
	space_state = get_tree().get_root().get_world_2d().direct_space_state

# Register a cover object with the system
func register_cover_object(object):
	if not cover_objects.has(object):
		cover_objects.append(object)

# Unregister a cover object
func unregister_cover_object(object):
	var idx = cover_objects.find(object)
	if idx != -1:
		cover_objects.remove_at(idx)

# Evaluate cover for a position
func evaluate_cover(position: Vector2) -> Dictionary:
	var result = {
		"in_cover": false,
		"level": 0.0,  # 0.0 to 1.0 (no cover to full cover)
		"direction": Vector2.ZERO,  # Direction the cover is protecting from
		"cover_object": null
	}
	
	# Find the nearest cover object
	var nearest_cover = _find_nearest_cover_object(position)
	
	if nearest_cover:
		# Calculate direction to cover
		var direction_to_cover = (nearest_cover.global_position - position).normalized()
		
		# Check cover in multiple directions
		var directions_checked = 0
		var directions_covered = 0
		
		for i in range(cover_raycast_count):
			var angle = (2.0 * PI / cover_raycast_count) * i
			var check_direction = Vector2(cos(angle), sin(angle))
			
			# Skip directions that are away from the cover object (within 90 degrees)
			if check_direction.dot(direction_to_cover) > 0:
				continue
			
			directions_checked += 1
			
			# Cast a ray from the unit position in the current direction
			var query = PhysicsRayQueryParameters2D.new()
			query.from = position
			query.to = position + (check_direction * cover_raycast_distance)
			query.collision_mask = 0b10  # Assuming cover objects are on layer 2
			
			var hit = space_state.intersect_ray(query)
			
			if hit and hit.collider == nearest_cover:
				directions_covered += 1
				
				# If we haven't set a cover direction yet, use this one
				if result.direction == Vector2.ZERO:
					result.direction = -check_direction
		
		# Calculate cover level based on how many directions are covered
		if directions_checked > 0:
			result.level = float(directions_covered) / float(directions_checked)
			result.in_cover = result.level > 0.0
			result.cover_object = nearest_cover
	
	return result

# Find the nearest cover object to a position
func _find_nearest_cover_object(position: Vector2):
	var nearest = null
	var nearest_distance = cover_check_radius
	
	for cover in cover_objects:
		var distance = position.distance_to(cover.global_position)
		
		if distance < nearest_distance:
			nearest = cover
			nearest_distance = distance
	
	return nearest
