extends Node3D
class_name Unit


# Store: player_id (int), hex_x (int), hex_z (int)
var config: Dictionary = {}
var unit_display_name: String = ""
var unit_types = [] # Tags like "military", "scout"
var player_id: int = 0
var move_speed: float = 0.0
var size_hex: float = 0.0 # Radius in hex units
var max_health: float = 0.0
var current_health: float = 0.0
var scale_factor: float = 1.0 # Store scale factor
var current_tile: Tile = null

var formation_slot: int = -1
var formation_position: Vector3 = Vector3.ZERO

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
	max_health = config.get("max_health", 1.0)
	current_health = max_health
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

func _ready():
	# Unit initialization is handled in _init().
	var map_node = get_parent()
	if map_node and is_instance_valid(map_node.get_node_or_null("Grid")):
		grid = map_node.get_node("Grid")
	
	# Movement will be initiated by Game.gd after flow fields are calculated.
	if unit_types.has("military"):
		is_moving = false # Ensure movement is off initially

# Returns the unit's height based on its mesh and scale factor
func get_unit_height() -> float:
	if mesh_instance and mesh_instance.mesh:
		var aabb_size: Vector3 = mesh_instance.mesh.get_aabb().size
		return aabb_size.y * scale_factor
	return 0.0

# Called every physics frame (60 times per second by default)
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
		print("Unit %d: No next tile from flow field. Stopping." % player_id)
		is_moving = false
		return
	
	# 3. Check for enemy units on the next tile
	if next_tile.has_enemy_units(player_id):
		# Cannot move to a tile occupied by an enemy
		print("Unit %d: Tile (%s) occupied by enemy unit. Stopping." % [player_id, next_tile.get_coords()])
		is_moving = false
		return
		
	# 4. Check for available formation slot and claim it
	if not try_claim_new_slot(next_tile, current_tile):
		# Could not claim a slot on the next tile, likely full
		print("Unit %d: Could not claim formation slot on Tile (%s). Stopping." % [player_id, next_tile.get_coords()])
		is_moving = false
		return
	
	var tile_position: Vector3 = next_tile.world_pos
	formation_position = tile_position + Vector3(
		next_tile.FORMATION_POSITIONS[formation_slot].x,
		get_unit_height() / 2.0,
		next_tile.FORMATION_POSITIONS[formation_slot].y
	)
	is_moving = true
	target_world_pos = formation_position
	
	return
