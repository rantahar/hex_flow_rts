extends Node3D
class_name Unit


# Store: player_id (int), hex_x (int), hex_z (int)
var config: Dictionary = {}
var unit_display_name: String = ""
var unit_types = [] # Tags like "military", "scout"
var player_id: int = 0
var hex_x: int = 0
var hex_z: int = 0
var move_speed: float = 0.0
var size_hex: float = 0.0 # Radius in hex units
var max_health: float = 0.0
var current_health: float = 0.0
var scale_factor: float = 1.0 # Store scale factor

var formation_slot: int = -1
var formation_position: Vector3 = Vector3.ZERO

var is_moving: bool = false
var target_world_pos: Vector3 = Vector3.ZERO
var target_hex_coords: Vector2i = Vector2i.ZERO
var grid: Grid = null

var mesh_instance: MeshInstance3D
var movement_timer: Timer

func _init(unit_config: Dictionary, p_player_id: int, p_hex_x: int, p_hex_z: int, world_pos: Vector3):
	config = unit_config
	player_id = p_player_id
	hex_x = p_hex_x
	hex_z = p_hex_z
	
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
			hex_x = target_hex_coords.x
			hex_z = target_hex_coords.y
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
	
	# 2. Look up flow direction for current tile
	var current_coords = Vector2i(hex_x, hex_z)
	var current_tile = grid.tiles.get(current_coords)
	
	if not current_tile:
		push_warning("Unit %d: Current tile (%s) not found in grid. Stopping." % [player_id, current_coords])
		is_moving = false
		return
		
	# 3. Get next tile based on flow field and calculate next world position
	var next_tile = flow_field.get_next_tile(current_tile, grid)
	
	# Determine if the unit is stopping on the current tile (no next tile defined by flow field)
	var stopping_on_tile: bool = not next_tile
	
	# If leaving tile: release formation_slot if assigned
	if not stopping_on_tile and formation_slot != -1:
		current_tile.release_formation_slot(formation_slot)
		formation_slot = -1
		formation_position = Vector3.ZERO
		
	if stopping_on_tile:
		# Unit is stopping.
		if formation_slot != -1:
			# Already stopped in formation, do nothing
			is_moving = false
			print("Unit %d (%s) at (%d, %d) stopped in formation." % [player_id, unit_display_name, current_coords.x, current_coords.y])
			return
		
		# Try to claim a formation slot on the current tile
		formation_slot = current_tile.claim_formation_slot()
		
		if formation_slot != -1:
			# Successfully claimed slot. Calculate formation position and start moving towards it.
			var pos_offset_2d: Vector2 = current_tile.FORMATION_POSITIONS[formation_slot]
			var tile_height: float = get_parent().get_height_at_world_pos(current_tile.world_pos)
			var unit_height: float = get_unit_height()
			
			# Calculate final resting world position
			formation_position = Vector3(
				current_tile.world_pos.x + pos_offset_2d.x,
				tile_height + unit_height * 0.5,
				current_tile.world_pos.z + pos_offset_2d.y
			)
			
			is_moving = true
			print("Unit %d (%s) at (%d, %d) claimed slot %d, moving to formation pos." % [player_id, unit_display_name, current_coords.x, current_coords.y, formation_slot])
			return
		else:
			# No formation slot available (tile full)
			is_moving = false
			print("Unit %d (%s) at (%d, %d) stopping, tile full or no flow direction." % [player_id, unit_display_name, current_coords.x, current_coords.y])
			return
			
	# If we reach here, we are moving to a NEXT tile (next_tile is valid)
	var next_coords = next_tile.get_coords()
	var next_world_pos = next_tile.world_pos
	
	# print("Unit %d at (%d, %d) calculated next move to (%d, %d)." % [player_id, current_coords.x, current_coords.y, next_coords.x, next_coords.y])
	
	# 4. Update target position (including height offset) and start moving
	target_hex_coords = next_coords
	
	var tile_height: float = get_parent().get_height_at_world_pos(next_world_pos)
	var unit_height: float = get_unit_height()
	
	target_world_pos = Vector3(next_world_pos.x, tile_height + unit_height * 0.5, next_world_pos.z)
	is_moving = true
	# print("Unit %d starting movement." % player_id)
