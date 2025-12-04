extends Node3D
class_name Unit
const HealthBar3D = preload("res://src/HealthBar3D.gd")

var health_bar: HealthBar3D


# Store: player_id (int), hex_x (int), hex_z (int)
var config: Dictionary = {}
var unit_display_name: String = ""
var unit_types = [] # Tags like "military", "scout"
var player_id: int = 0
var move_speed: float = 0.0
var size_hex: float = 0.0 # Radius in hex units
var max_health: float = 0.0
var health: float = 0.0
var attack_damage: float = 0.0
var attack_rate: float = 0.0
var last_attack_time: float = 0.0
var scale_factor: float = 1.0 # Store scale factor
var current_tile: Tile = null
var formation_slot: int = -1
var formation_position: Vector3 = Vector3.ZERO
var in_combat: bool = false

var is_moving: bool = false
var target_world_pos: Vector3 = Vector3.ZERO
var grid: Grid = null

var mesh_instance: MeshInstance3D
var movement_timer: Timer


func _init(unit_config: Dictionary, p_player_id: int, p_current_tile: Tile, world_pos: Vector3):
	config = unit_config
	player_id = p_player_id
	current_tile = p_current_tile
	
	# Initialize stats from config
	move_speed = config.get("move_speed", 0.0)
	size_hex = config.get("size", 0.0)
	# Combat stats
	max_health = config.get("max_health", 100.0)
	health = max_health
	attack_damage = config.get("attack_damage", 20.0)
	attack_rate = config.get("attack_rate", 1.0)
	
	unit_display_name = config.get("display_name", "Unit")
	unit_types = config.get("unit_types", []) # Remove type hint on declaration to prevent runtime error
	
	# Set up periodic movement checks for military units
	if unit_types.has("military"):
		movement_timer = Timer.new()
		movement_timer.wait_time = 0.5 # Check every half second when idle
		movement_timer.autostart = true
		movement_timer.connect("timeout", _on_movement_check_timeout)
		add_child(movement_timer)
	
	# Set position to planar world position for now. Height will be corrected after adding to tree.
	position = Vector3(world_pos.x, world_pos.y, world_pos.z)
	
	# Load mesh resource dynamically
	var mesh_path: String = config.get("mesh_path", "")
	var mesh: Mesh = load(mesh_path)
	if not mesh:
		push_error("Unit %s: Failed to load mesh at path: %s" % [unit_display_name, mesh_path])
	
	# Create mesh instance
	mesh_instance = MeshInstance3D.new()
	mesh_instance.name = "UnitMeshInstance"
	mesh_instance.mesh = mesh
	
	# Calculate target size based on hex unit size (Grid.HEX_SCALE * size_hex)
	var target_unit_world_radius: float = Grid.HEX_SCALE * size_hex
	
	# Calculate the current horizontal size of the mesh (max of X and Z dimensions)
	var aabb_size: Vector3 = mesh.get_aabb().size
	# We want the radius of the mesh for scaling calculation (half of max horizontal size)
	var current_mesh_radius: float = maxf(aabb_size.x, aabb_size.z) / 2.0
	
	# Calculate the required uniform scale factor and store it
	if current_mesh_radius > 0:
		scale_factor = target_unit_world_radius / current_mesh_radius
	else:
		scale_factor = 1.0
		
	mesh_instance.scale = Vector3(scale_factor, scale_factor, scale_factor)
	add_child(mesh_instance)

	   # Health Bar setup
	health_bar = HealthBar3D.new()
	add_child(health_bar)
	
	# Get unit mesh AABB size
	var mesh_aabb_size: Vector3 = mesh_instance.mesh.get_aabb().size
	# Calculate scaled unit size for proportional health bar
	var scaled_unit_size: Vector3 = mesh_aabb_size * scale_factor
	health_bar.setup(scaled_unit_size)
	
	health_bar.update_health(health, max_health)

# Called when this unit takes damage.
func take_damage(amount: float):
	health -= amount
	# Clamp current_health to minimum of 0
	health = maxi(0.0, health)
	
	# Call health_bar.update_health
	if is_instance_valid(health_bar):
		health_bar.update_health(health, max_health)
		
	print("Unit %d (Player %d): Took %f damage, remaining health: %f" % [get_instance_id(), player_id, amount, health])
	
	if health <= 0:
		# 1. Get Game node to access Player data
		var game_node = get_parent().get_parent() # Unit -> Map -> Game
		if is_instance_valid(game_node) and game_node.name == "Game":
			var player: Player = game_node.get_player(player_id)
			if player and player.units.has(self):
				# Remove self from Player.units array
				player.units.erase(self)
				
		# 2. Release formation slot on current tile
		if current_tile and formation_slot != -1:
			current_tile.release_formation_slot(formation_slot)
			# Do NOT reset formation_slot to -1 here, current_tile.release_formation_slot sets it to null in the tile, 
			# but unit needs to keep formation_slot for self-reference
			# The Unit object will be freed immediately, so resetting formation_slot is not critical, but clearing the tile reference is.
			
		# 3. Remove from scene
		queue_free()

func _ready():
	# Unit initialization is handled in _init().
	var map_node = get_parent()
	if map_node and is_instance_valid(map_node.get_node_or_null("Grid")):
		grid = map_node.get_node("Grid")
	
	_correct_height()
	
	# Movement will be initiated by Game.gd after flow fields are calculated.
	if unit_types.has("military"):
		is_moving = false # Ensure movement is off initially
		

# Returns the unit's height based on its mesh and scale factor
func get_unit_height() -> float:
	if mesh_instance and mesh_instance.mesh:
		var aabb_size: Vector3 = mesh_instance.mesh.get_aabb().size
		return aabb_size.y * scale_factor
	return 0.0

func _get_ground_height(pos_xz: Vector3) -> float:
	if not is_inside_tree():
		push_error("Unit: Cannot raycast if not inside tree.")
		return pos_xz.y

	var space_state = get_world_3d().direct_space_state
	# Cast from high above the map down to below the map
	var start_point = Vector3(pos_xz.x, 100.0, pos_xz.z)
	var end_point = Vector3(pos_xz.x, -100.0, pos_xz.z)

	var query = PhysicsRayQueryParameters3D.create(start_point, end_point)
	
	# Units and their collision shapes should be excluded from the raycast if they exist,
	# but since they are KinematicBody3D (or Node3D) and not part of the ground,
	# a simple query should suffice for now assuming only the Map/Tile geometry is in the way.
	# If map tiles are in a specific collision layer, we could restrict the search.
	# For simplicity, we assume the ground is the first thing hit.
	var result = space_state.intersect_ray(query)

	if result.is_empty():
		# Fallback: if no ground found, assume the current Y level.
		return position.y
	
	return result.position.y

func _correct_height():
	var ground_y = _get_ground_height(position)
	var unit_half_height = get_unit_height() / 2.0
	position.y = ground_y + unit_half_height


# Called every physics frame (60 times per second by default)
# Called every frame for time-dependent combat logic
func _process(delta: float):
	if in_combat and unit_types.has("military"):
		_try_attack()

# Finds the closest enemy unit in any neighboring tile (Euclidean distance squared)
# Returns the closest enemy unit instance, or null.
func _get_closest_enemy_in_range() -> Unit:
	if not current_tile:
		return null
	
	var closest_enemy: Unit = null
	# Initialize minimum distance squared to a very large number
	var min_distance_sq: float = 1e20
	
	# Only check neighbors for combat range
	for neighbor_tile in current_tile.neighbors:
		if is_instance_valid(neighbor_tile) and neighbor_tile.has_enemy_units(player_id):
			# Iterate over occupied slots on the enemy tile
			for unit_ref in neighbor_tile.occupied_slots:
				if is_instance_valid(unit_ref) and unit_ref.player_id != player_id:
					# Calculate distance squared to this enemy unit's position
					var distance_sq = position.distance_squared_to(unit_ref.position)
					
					if distance_sq < min_distance_sq:
						min_distance_sq = distance_sq
						closest_enemy = unit_ref
						
	return closest_enemy

func _try_attack():
	# Check if attack cooldown is ready
	var current_time = Time.get_unix_time_from_system()
	if (current_time - last_attack_time) < attack_rate:
		return
		
	var target_unit = _get_closest_enemy_in_range()
	
	if is_instance_valid(target_unit):
		# Attack
		target_unit.take_damage(attack_damage)
		last_attack_time = current_time
		
		# Optional: Rotate to face enemy (Horizontal only)
		var direction = target_unit.position - position
		_rotate_to_face(direction)
	else:
		# If we are flagged as in_combat but no enemies are found, exit combat state.
		in_combat = false

func _physics_process(delta):
	if not is_moving:
		return

	var target_destination: Vector3 = target_world_pos
	var arriving_at_formation_pos: bool = false
	
	if formation_slot != -1:
		target_destination = formation_position
		arriving_at_formation_pos = true

	var movement_vector: Vector3 = target_destination - position
	var distance_to_target: float = movement_vector.length()
	var arrival_threshold: float = move_speed * delta
	
	# Check if we have arrived at the target
	if distance_to_target < arrival_threshold:
		position = target_destination
		is_moving = false
		
		if not arriving_at_formation_pos:
			# We arrived at a new tile center, update coords and decide next move
			# hex_x and hex_z are deprecated, we rely on current_tile reference updated via try_claim_new_slot
			# We update hex_x/hex_z for coordinate tracking in this instance if needed, but not required by unit class itself
			_move_to_next_tile()
		
		return

	# Move towards target
	var direction: Vector3 = movement_vector.normalized()
	position += direction * move_speed * delta
	
	# Rotate unit to face direction of movement
	_rotate_to_face(direction)

# Rotates the unit instantly to face the given direction vector (horizontal only)
func _rotate_to_face(direction: Vector3):
	# Only consider X and Z components for rotation
	var planar_direction = Vector2(direction.x, direction.z).normalized()
	if planar_direction != Vector2.ZERO:
		# Calculate rotation angle around the Y axis
		# Note: Godot's 3D forward is -Z. A direction vector (0, -1) points forward.
		var target_rotation_y = atan2(planar_direction.x, planar_direction.y)
		rotation.y = target_rotation_y

# --- Timer Callback ---

func _on_movement_check_timeout():
	# Only military units follow flow field and only when idle
	if unit_types.has("military") and not is_moving:
		_move_to_next_tile()
	
# Calculates the next tile to move to based on the player's flow field.
# This function is called on arrival OR by the periodic movement timer when idle.
# Attempts to claim a formation slot on a new tile. If successful, renounces the previous slot.
func try_claim_new_slot(new_tile: Tile, old_tile: Tile) -> bool:
	var new_slot = new_tile.claim_formation_slot(self)
	
	if new_slot != -1:
		# 1. Deregister from current (old) tile
		if formation_slot != -1:
			old_tile.release_formation_slot(formation_slot)
			
		# 2. Update unit's slot state
		formation_slot = new_slot
		current_tile = new_tile
		return true
	
	return false

func _move_to_next_tile():
	if not grid:
		push_error("Unit %d: Grid is not initialized." % player_id)
		return

	# 1. Get Game node to access Player data
	var game_node = get_parent().get_parent() # Unit -> Map -> Game
	if not is_instance_valid(game_node) or game_node.name != "Game":
		push_error("Unit %d: Could not find Game node." % player_id)
		return
		
	var player: Player = game_node.get_player(player_id)
	if not player or not player.flow_field:
		push_warning("Unit %d: Player or FlowField missing. Stopping." % player_id)
		is_moving = false
		return
		
	var flow_field = player.flow_field

	# 2. Determine next tile from flow field
	var next_tile: Tile = flow_field.get_next_tile(current_tile, grid)
	if not next_tile:
		# No valid next tile (e.g., at target or blocked)
		is_moving = false
		return
	
	# 3. Check for enemies in neighboring tiles (1 hex range)
	if _get_closest_enemy_in_range():
		# Cannot move if an enemy is in range
		is_moving = false
		in_combat = true
		return
		
	# 4. Check for available formation slot and claim it
	if not try_claim_new_slot(next_tile, current_tile):
		# Could not claim a slot on the next tile, likely full
		is_moving = false
		return
	
	# 1. Calculate the target world position in 2D (X/Z) relative to the tile center
	var target_xz_pos: Vector3 = next_tile.world_pos + Vector3(
		next_tile.FORMATION_POSITIONS[formation_slot].x,
		0.0,
		next_tile.FORMATION_POSITIONS[formation_slot].y
	)
	
	# 2. Raycast downward from the target X/Z position to find the actual ground height (Y)
	var ground_y: float = _get_ground_height(target_xz_pos)
	
	# 3. Set the formation position: X/Z from calculation, Y from ground height + half unit height.
	formation_position = Vector3(
		target_xz_pos.x,
		ground_y + get_unit_height() / 2.0,
		target_xz_pos.z
	)
	# 5. We successfully claimed a slot and there are no adjacent enemies in range (checked in step 3).
	in_combat = false # Exit combat state before moving
	is_moving = true
	target_world_pos = formation_position
	
	return
