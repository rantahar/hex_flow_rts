extends Node3D
class_name Unit

const GameData = preload("res://data/game_data.gd")

var health_bar: HealthBar3D
var muzzle_flash: OmniLight3D
var muzzle_flash_timer: Timer

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
var attack_check_timer: Timer


func _init(unit_config: Dictionary, p_player_id: int, p_current_tile: Tile, world_pos: Vector3):
	"""
	Initializes the unit with configuration, player ID, starting tile, and world position.
	Sets up unit stats, mesh instance with scaling, health bar, and muzzle flash.

	Arguments:
	- unit_config (Dictionary): Configuration dictionary containing unit stats (e.g., move_speed, max_health, mesh_path).
	- p_player_id (int): The ID of the player who owns this unit.
	- p_current_tile (Tile): The tile the unit is currently standing on.
	- world_pos (Vector3): The initial world position of the unit (planar X/Z, Y is corrected later).
	"""
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
	
	# Set position to planar world position for now. Height will be corrected after adding to tree.
	position = Vector3(world_pos.x, world_pos.y, world_pos.z)

	# Call initialization helpers
	_setup_mesh(config)
	_setup_health_bar()
	_setup_combat_effects()
	_setup_movement_timer()

# --- Initialization Helpers ---

func _setup_mesh(unit_config: Dictionary) -> void:
	"""
	Loads the unit's 3D mesh, calculates the necessary scale factor based on
	the configured hex size, and creates and adds the MeshInstance3D node.
	
	Arguments:
	- unit_config (Dictionary): Configuration dictionary containing mesh_path and size_hex.
	"""
	var mesh_path: String = unit_config.get("mesh_path", "")
	var mesh: Mesh = load(mesh_path)
	if not mesh:
		push_error("Unit %s: Failed to load mesh at path: %s" % [unit_display_name, mesh_path])
		return
	
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

func _setup_health_bar() -> void:
	"""
	Creates and configures the HealthBar3D node based on the scaled unit mesh size.
	Initializes the health bar display.
	"""
	# Health Bar setup
	health_bar = HealthBar3D.new()
	add_child(health_bar)
	
	# Get unit mesh AABB size
	var mesh_aabb_size: Vector3 = mesh_instance.mesh.get_aabb().size
	# Calculate scaled unit size for proportional health bar
	var scaled_unit_size: Vector3 = mesh_aabb_size * scale_factor
	health_bar.setup(scaled_unit_size)
	
	health_bar.update_health(health, max_health)

func _setup_combat_effects() -> void:
	"""
	Sets up the OmniLight3D (muzzle flash) and the MuzzleFlashTimer for visual feedback during attacks.
	"""
	# Muzzle Flash setup (OmniLight3D)
	muzzle_flash = OmniLight3D.new()
	muzzle_flash.name = "MuzzleFlash"
	muzzle_flash.light_energy = 0.0 # Hidden by default
	muzzle_flash.omni_range = 0.5
	muzzle_flash.light_color = Color(1.0, 0.7, 0.3)
	muzzle_flash.position = Vector3(0.05, 0, 0) # Front-right relative to unit
	add_child(muzzle_flash)
	
	# Muzzle Flash Timer setup
	muzzle_flash_timer = Timer.new()
	muzzle_flash_timer.name = "MuzzleFlashTimer"
	muzzle_flash_timer.wait_time = 0.15
	muzzle_flash_timer.one_shot = true
	muzzle_flash_timer.connect("timeout", _on_muzzle_flash_timeout)
	add_child(muzzle_flash_timer)

func _setup_movement_timer() -> void:
	"""
	Sets up the periodic movement check timer and the attack check timer if the unit
	is tagged as "military".
	"""
	if unit_types.has("military"):
		# Movement Timer setup
		movement_timer = Timer.new()
		movement_timer.wait_time = 0.5 # Check every half second when idle
		movement_timer.autostart = true
		movement_timer.connect("timeout", _on_movement_check_timeout)
		add_child(movement_timer)
		
		# Attack Check Timer setup
		attack_check_timer = Timer.new()
		attack_check_timer.wait_time = 0.25
		attack_check_timer.autostart = false
		attack_check_timer.connect("timeout", _on_attack_check_timeout)
		add_child(attack_check_timer)

# Called when this unit takes damage.
func take_damage(amount: float):
	"""
	Reduces the unit's health by the specified amount and updates the health bar.
	If health drops to 0 or below, the unit is destroyed.

	Arguments:
	- amount (float): The amount of damage to inflict.
	"""
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
	"""
	Called when the node enters the scene tree for the first time.
	Initializes the Grid reference and corrects the unit's height based on the ground level.
	"""
	# Unit initialization is handled in _init().
	var map_node = get_parent()
	if map_node and is_instance_valid(map_node.get_node_or_null("Grid")):
		grid = map_node.get_node("Grid")
	
	_correct_height()

	# Apply current strategic zoom state
	var game_node = get_parent().get_parent()
	if is_instance_valid(game_node) and game_node.has_method("get_strategic_zoom"):
		set_strategic_zoom(game_node.get_strategic_zoom())

	# Movement will be initiated by Game.gd after flow fields are calculated.
	if unit_types.has("military"):
		is_moving = false # Ensure movement is off initially
		

# Returns the unit's height based on its mesh and scale factor
func get_unit_height() -> float:
	"""
	Calculates the total height of the unit model in world units (Y dimension).

	Returns:
	- float: The scaled height of the unit's mesh.
	"""
	if mesh_instance and mesh_instance.mesh:
		var aabb_size: Vector3 = mesh_instance.mesh.get_aabb().size
		return aabb_size.y * scale_factor
	return 0.0


func _correct_height():
	"""
	Adjusts the unit's Y position to correctly sit on the ground, centered vertically.
	"""
	var map_node = get_parent()
	var ground_y = map_node.get_height_at_world_pos(position)
	var unit_half_height = get_unit_height() / 2.0
	position.y = ground_y + unit_half_height


# Called every physics frame (60 times per second by default)
# Called every frame for time-dependent combat logic
func _process(_delta: float):
	"""
	Called every frame. Handles combat logic for military units, allowing them to attack targets.

	Arguments:
	- delta (float): The elapsed time since the previous frame.
	"""
	pass

# Finds the closest enemy unit in any neighboring tile (Euclidean distance squared)
# Returns the closest enemy unit instance, or null.
# Finds the closest enemy unit or structure in range (Euclidean distance squared)
# Returns the closest enemy instance (Unit or Structure), or null.
func _get_enemy_tiles_in_range() -> Array[Tile]:
	"""
	BFS from current_tile up to ceil(attack_range_hex) hops.
	Returns all tiles within range that contain a reserved enemy unit or enemy structure,
	in BFS order (nearest tiles first). Returns empty array for range-0 units.
	"""
	if not current_tile or not grid:
		return []
	var max_hops: int = ceili(config.get("attack_range", 0.0))
	if max_hops <= 0:
		return []

	var result: Array[Tile] = []
	var visited: Dictionary = { current_tile: true }
	var frontier: Array[Tile] = [current_tile]

	for _depth in range(max_hops + 1):
		var next_frontier: Array[Tile] = []
		for tile_ref in frontier:
			if tile_ref.is_flow_target(player_id):
				result.append(tile_ref)
			for neighbor in tile_ref.neighbors:
				if not visited.has(neighbor):
					visited[neighbor] = true
					next_frontier.append(neighbor)
		frontier = next_frontier

	return result

func _get_closest_enemy_in_range() -> Node3D:
	"""
	Returns the nearest stopped enemy unit or enemy structure within attack range.
	Uses _get_enemy_tiles_in_range() (BFS order = nearest first) and filters for
	stopped units (is_moving == false). Structures are always considered stopped.

	Returns:
	- Node3D: The closest targetable enemy (Unit or Structure), or null if none found.
	"""
	for tile_ref in _get_enemy_tiles_in_range():
		for unit_ref in tile_ref.occupied_slots:
			if is_instance_valid(unit_ref) \
					and unit_ref.player_id != player_id \
					and not unit_ref.is_moving:
				return unit_ref
		if tile_ref.structure != null \
				and is_instance_valid(tile_ref.structure) \
				and tile_ref.structure.player_id != player_id:
			return tile_ref.structure
	return null

func _try_attack():
	"""
	Checks if the unit is ready to attack. If an enemy is in range, it deals damage,
	activates the muzzle flash, and rotates the unit to face the target.
	If no enemy is found, combat state is exited.
	"""
	# Check if attack cooldown is ready
	var current_time = Time.get_unix_time_from_system()
	if (current_time - last_attack_time) < attack_rate:
		return
		
	var target_unit = _get_closest_enemy_in_range()
	
	if is_instance_valid(target_unit):
		# Attack
		target_unit.take_damage(attack_damage)
		
		# Muzzle flash activation
		muzzle_flash.light_energy = 1.0
		muzzle_flash_timer.start()
		
		last_attack_time = current_time
		
		# Optional: Rotate to face enemy (Horizontal only)
		var direction = target_unit.position - position
		_rotate_to_face(direction)
	else:
		# If we are flagged as in_combat but no enemies are found, exit combat state.
		in_combat = false
		if attack_check_timer and attack_check_timer.is_stopped() == false:
			attack_check_timer.stop()

func _physics_process(delta):
	"""
	Called every physics frame. Handles smooth movement towards the target world position.
	Updates the unit's position and rotation based on movement speed and direction.

	Arguments:
	- delta (float): The elapsed time since the previous physics frame.
	"""
	if not is_moving:
		return

	var target_destination: Vector3 = target_world_pos
	if formation_slot != -1:
		target_destination = formation_position

	# Calculate effective speed based on tile cost (higher cost = slower)
	var tile_cost: float = 1.0
	if is_instance_valid(current_tile):
		if current_tile.has_road:
			tile_cost = GameData.ROAD_CONFIG.road_tile_cost
		else:
			tile_cost = current_tile.cost
	var effective_speed: float = move_speed / maxf(tile_cost, 0.1)

	var movement_vector: Vector3 = target_destination - position
	var distance_to_target: float = movement_vector.length()
	var arrival_threshold: float = effective_speed * delta

	# Check if we have arrived at the target
	if distance_to_target < arrival_threshold:
		position = target_destination
		is_moving = false

		# Immediately check for the next move or combat upon arrival.
		_move_to_next_tile()

		return

	var direction: Vector3 = movement_vector.normalized()
	position += direction * effective_speed * delta
	
	# Rotate unit to face direction of movement
	_rotate_to_face(direction)

# Rotates the unit instantly to face the given direction vector (horizontal only)
func _rotate_to_face(direction: Vector3):
	"""
	Rotates the unit instantly around the Y-axis to face the given direction vector (horizontal component only).

	Arguments:
	- direction (Vector3): The direction vector towards which the unit should face.
	"""
	# Only consider X and Z components for rotation
	var planar_direction = Vector2(direction.x, direction.z).normalized()
	if planar_direction != Vector2.ZERO:
		# Calculate rotation angle around the Y axis
		# Note: Godot's 3D forward is -Z. A direction vector (0, -1) points forward.
		var target_rotation_y = atan2(planar_direction.x, planar_direction.y)
		rotation.y = target_rotation_y

# --- Timer Callback ---

func _on_movement_check_timeout():
	"""
	Callback for the periodic movement timer. Triggers movement calculation if the military unit is currently idle.
	"""
	# Only military units follow flow field and only when idle
	if unit_types.has("military") and not is_moving:
		_move_to_next_tile()
	
# Calculates the next tile to move to based on the player's flow field.
# This function is called on arrival OR by the periodic movement timer when idle.
# Attempts to claim a formation slot on a new tile. If successful, renounces the previous slot.
func try_claim_new_slot(new_tile: Tile, old_tile: Tile) -> bool:
	"""
	Attempts to claim a formation slot on a new tile. If successful, it releases the slot on the old tile.

	Arguments:
	- new_tile (Tile): The Tile object where the unit attempts to move.
	- old_tile (Tile): The Tile object the unit is currently occupying.

	Returns:
	- bool: True if a slot was successfully claimed on the new tile, false otherwise.
	"""
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
	"""
	Calculates the next tile based on the player's flow field (target destination).
	Checks for enemies in range, attempts to claim a slot on the next tile, and if successful,
	calculates the precise world target position and initiates movement.
	"""
	if not grid:
		push_error("Unit %d: Grid is not initialized." % player_id)
		return

	# 1. Get Game and Map nodes
	var map_node = get_parent()
	var game_node = map_node.get_parent() # Unit -> Map -> Game
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
	
	# 2.5. Stop if any tile within firing range has an enemy reservation
	if not _get_enemy_tiles_in_range().is_empty():
		is_moving = false
		if not in_combat and unit_types.has("military"):
			in_combat = true
			if attack_check_timer:
				attack_check_timer.start()
			_try_attack()
		return

	# Defense-in-depth: hold position unless a companion or structure is present.
	if current_tile.structure == null:
		var friendly_count := 0
		var i_am_leader := true
		for i in range(current_tile.occupied_slots.size()):
			var occupant = current_tile.occupied_slots[i]
			if occupant != null and is_instance_valid(occupant) and occupant.player_id == player_id:
				friendly_count += 1
				if i < formation_slot:
					i_am_leader = false
		if friendly_count < 2 or not i_am_leader:
			is_moving = false
			return

	# 3. Check for available formation slot and claim it
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
	
	# 2. Query Map for the actual ground height (Y)
	var ground_y: float = map_node.get_height_at_world_pos(target_xz_pos)
	
	# 3. Set the formation position: X/Z from calculation, Y from ground height + half unit height.
	formation_position = Vector3(
		target_xz_pos.x,
		ground_y,
		target_xz_pos.z
	)
	# 5. We successfully claimed a slot and there are no adjacent enemies in range (checked in step 3).
	in_combat = false # Exit combat state before moving
	is_moving = true
	target_world_pos = formation_position
	
	return

# --- Muzzle Flash Timer Callback ---

func _on_attack_check_timeout():
	"""
	Timer callback to periodically check if the unit can perform an attack while in combat.
	If combat is active, calls _try_attack(). If combat is inactive, stops the timer.
	"""
	if in_combat:
		_try_attack()
	elif attack_check_timer and attack_check_timer.is_stopped() == false:
		attack_check_timer.stop()


func _on_muzzle_flash_timeout():
	"""
	Callback for the MuzzleFlashTimer. Hides the muzzle flash light by setting its energy to 0.0.
	"""
	muzzle_flash.light_energy = 0.0

func set_strategic_zoom(is_strategic: bool) -> void:
	if is_instance_valid(mesh_instance):
		mesh_instance.visible = not is_strategic
	if is_instance_valid(health_bar):
		health_bar.visible = not is_strategic
