class_name Player
extends Node3D

signal resources_updated(new_resources: float)

# Exported player ID.
@export var id: int
const GameData = preload("res://data/game_data.gd")
const GameConfig = preload("res://data/game_config.gd")
const Structure = preload("res://src/core/Structure.gd")
const Tile = preload("res://src/core/Tile.gd")
const Builder = preload("res://src/Builder.gd")

# Required for Game.gd initialization logic
var color: Color = Color.WHITE
var target: Vector2i = Vector2i.ZERO
var flow_field = null # Assumes FlowField is globally available or handled by Game.gd
var units: Array = []
var builders: Array = []
var structures: Array[Structure] = []
# Dictionary for O(1) structure lookup by grid coordinates: {Vector2i: Structure}
var structures_by_coord: Dictionary = {}
var resources: float = 0.0
var config: Dictionary = {} # Store player configuration for type checking, etc.
var spawn_tile: Tile


# We assume Unit.gd is used directly as the unit's class/resource definition.


# Method: spawn_unit(hex_x: int, hex_z: int, map_node: Node3D) -> Unit
func spawn_unit(hex_x: int = -1, hex_z: int = -1, map_node: Node3D = null, unit_type: String = "infantry"):
	"""
	Instantiates a new unit of the specified type at the designated spawn tile (or given coordinates).
	The unit is initialized with player ID, added to the map, positioned in a formation slot, and added to the player's unit list.

	Arguments:
	- hex_x (int): Optional. The X grid coordinate for spawning. Defaults to -1 (uses spawn_tile).
	- hex_z (int): Optional. The Z grid coordinate for spawning. Defaults to -1 (uses spawn_tile).
	- map_node (Node3D): The Map node instance, needed for adding the unit to the scene and raycasting.
	- unit_type (String): The key string for the unit configuration in GameData.UNIT_TYPES.

	Returns:
	- Unit: The newly created Unit instance, or null if spawning fails.
	"""
	# Determine the tile to spawn on
	var tile_to_spawn_on: Tile
	if hex_x == -1 or hex_z == -1:
		if spawn_tile and map_node:
			tile_to_spawn_on = spawn_tile
		else:
			push_error("Player.spawn_unit: Cannot determine spawn location (spawn_tile or map_node missing).")
			return null
	else:
		# If coordinates are provided, look up the tile
		var grid = map_node.get_node_or_null("Grid")
		if not grid:
			push_error("Player.spawn_unit: Could not find Grid node in map")
			return null
		var coords = Vector2i(hex_x, hex_z)
		tile_to_spawn_on = grid.tiles.get(coords)

	if not map_node:
		push_error("Player.spawn_unit: Map node is null")
		return null
	
	# Validate tile
	if not is_instance_valid(tile_to_spawn_on) or not tile_to_spawn_on.walkable:
		push_error("Player.spawn_unit: Invalid or non-walkable tile provided/determined.")
		return null
	
	var coords = tile_to_spawn_on.get_coords()

	if not map_node:
		push_error("Player.spawn_unit: Map node is null")
		return null
	
	# We rely on the tile object for world position and coordinates
	var world_pos = tile_to_spawn_on.world_pos
	
	# 1. Instantiate Unit
	
	# Use the specified unit configuration dictionary
	if not GameData.UNIT_TYPES.has(unit_type):
		push_error("Player.spawn_unit: Invalid unit type: %s" % unit_type)
		return null
		
	var unit_config = GameData.UNIT_TYPES[unit_type]
	var unit = Unit.new(unit_config, id, tile_to_spawn_on, world_pos)
	
	# The Unit is initialized via Unit._init().
	
	if not is_instance_valid(unit):
		push_error("Player.spawn_unit: Unit instance creation failed.")
		return null
	
	# Add unit as child of map_node (required for raycasting to work)
	map_node.add_child(unit)
	
	# 3. Calculate correct vertical position using the map node's raycasting method
	var tile_height: float = map_node.get_height_at_world_pos(unit.position)
	var unit_height: float = unit.get_unit_height()
	
	unit.position.y = tile_height + unit_height * 0.5

	# Initial unit registration on spawn tile
	if tile_to_spawn_on:
		var slot = tile_to_spawn_on.claim_formation_slot(unit)
		if slot != -1:
			# Registration must be done here, as the Unit's internal logic will not run until the timer fires.
			# We ignore the user feedback that this line is redundant, as it is required for enemy detection.
			tile_to_spawn_on.occupied_slots[slot] = unit
			unit.formation_slot = slot
			unit.current_tile = tile_to_spawn_on # Ensure current_tile is set for Unit.gd usage
			
			# Set unit position to its initial formation slot position
			var pos_offset_2d: Vector2 = tile_to_spawn_on.FORMATION_POSITIONS[slot]
			var unit_pos_x = tile_to_spawn_on.world_pos.x + pos_offset_2d.x
			var unit_pos_z = tile_to_spawn_on.world_pos.z + pos_offset_2d.y
			
			unit.position.x = unit_pos_x
			unit.position.z = unit_pos_z
			
			# No need to set target_world_pos/is_moving here, unit will move to formation pos via _on_movement_check_timeout if needed
			
	
	# Add the unit to the player's internal list for tracking and counting
	units.append(unit)
	return unit


# Calculates the flow field for this player using the specified Grid.
# STEPS:
# 1. Check validation: grid not null, flow_field initialized, target valid in grid.
# 2. Creates targets dictionary {target_tile: 0.0}
# 3. Calls flow_field.calculate(targets, grid)
func calculate_flow(grid: Grid) -> void:
	"""
	Initiates the calculation of the player's flow field, targeting the player's designated `target` coordinates.

	Arguments:
	- grid (Grid): The map grid containing all Tile data required for pathfinding.
	"""
	# 1. Validation: check grid not null
	if not grid:
		push_error("Player %d.calculate_flow: Grid is null." % id)
		return
	
	# 1. Validation: check flow_field initialized (Constraint: it's initialized in Game.initialize_players())
	if not flow_field:
		push_error("Player %d.calculate_flow: flow_field is not initialized." % id)
		return
		
	# 1. Validation: check target valid
	if not grid.is_valid_coords(target):
		# This is a warning because the player target might legitimately be outside the map briefly,
		# but we should still skip calculation.
		push_warning("Player %d.calculate_flow: Target coordinates (%s) are invalid in grid. Skipping flow calculation." % [id, target])
		return
		
	# Retrieve target tile. We know it exists because of is_valid_coords check.
	var target_tile = grid.tiles.get(target)
	
	# 2. Create targets dictionary {target_tile: 0.0}
	# FlowField.calculate expects a dictionary of {Tile: float}
	var targets = {target_tile: 0.0}
	
	# 3. Calculate flow field
	flow_field.calculate(targets, grid)


# --- Initialization and Resource Management ---

func _init(p_id: int, config: Dictionary):
	# Initialize properties that cannot use default values or require calculation
	id = p_id
	self.config = config
	resources = config.get("starting_resources", 100.0)
	structures = [] # Initialized to empty array

func add_resources(amount: float):
	"""
	Adds a specific amount to the player's resources.
	"""
	resources += amount
	resources_updated.emit(resources)

func can_afford(structure_key: String) -> bool:
	"""
	Checks if the player has enough resources to afford the given structure type.
	"""
	var structure_config = GameData.STRUCTURE_TYPES.get(structure_key)
	if not structure_config:
		return false
	var cost = structure_config.get("cost", 0.0)
	return resources >= cost

# --- Structure and Unit Production Management ---

func _on_structure_unit_produced(unit_type: String, structure: Structure):
	"""
	Handles the unit production signal from a structure.
	Spawns the unit on the structure's current tile.
	"""
	print("Player %d received unit_produced signal for unit type '%s' from structure at tile %s." % [id, unit_type, structure.current_tile.get_coords()])
	if not is_instance_valid(structure):
		push_error("Player %d._on_structure_unit_produced: Invalid structure instance received." % id)
		return
		
	# Retrieve map_node via get_parent().get_node("Map") as instructed.
	var game_node = get_parent()
	if not is_instance_valid(game_node) or not game_node.has_node("Map"):
		push_error("Player %d._on_structure_unit_produced: Could not find Map node." % id)
		return
		
	var map_node = game_node.get_node("Map")
		
	# Spawn unit on the tile where the producing structure is located
	var tile = structure.current_tile
	if not is_instance_valid(tile):
		push_error("Player %d._on_structure_unit_produced: Structure tile is invalid." % id)
		return
		
	# Call the existing spawn_unit method, providing coordinates and map_node
	spawn_unit(tile.x, tile.z, map_node, unit_type)
	# Note: spawn_unit handles adding the unit to the player's `units` array internally.

func place_structure(structure_key: String, target_tile: Tile, map_node: Node3D, instant: bool = false) -> bool:
	"""
	Attempts to build a structure at the target tile, checking resource cost and tile availability.
	The structure is instantiated and added as a child of map_node.
	
	Arguments:
	- structure_key (String): The key in GameData.STRUCTURE_TYPES.
	- target_tile (Tile): The Tile instance where the structure should be built.
	- map_node (Node3D): The Map node instance, used as the parent for the new structure.
	
	Returns:
	- bool: True if the structure was successfully built, false otherwise.
	"""
	if not GameData.STRUCTURE_TYPES.has(structure_key):
		push_error("Player %d.place_structure: Invalid structure key '%s'." % [id, structure_key])
		return false
	
	var structure_config = GameData.STRUCTURE_TYPES[structure_key]
	
	# 1. All structures selected via the Build Menu are now considered buildable (Removed check for "buildable" flag).
		
	# 2. Check if target_tile is suitable for building (terrain)
	if not target_tile.is_buildable_terrain():
		push_error("Player %d.place_structure: Target tile (%s) terrain does not allow building." % [id, target_tile.get_coords()])
		return false

	# 3. Check if target_tile is free (occupation)
	if target_tile.structure != null:
		push_error("Player %d.place_structure: Target tile (%s) already occupied by a structure." % [id, target_tile.get_coords()])
		return false
		
	# 4. Check if player has enough resources
	var structure_cost: float = structure_config.get("cost", 0.0)
	if resources < structure_cost:
		push_error("Player %d.place_structure: Not enough resources. Required: %f, Have: %f" % [id, structure_cost, resources])
		return false
		
	# --- Checks Pass: Build Structure ---

	if not is_instance_valid(map_node):
		push_error("Player %d.place_structure: Invalid Map node reference." % id)
		return false

	# Create structure (ghost if not instant)
	var under_construction: bool = not instant
	var structure_instance = Structure.new(structure_config, structure_key, id, target_tile, target_tile.world_pos, under_construction)

	# Add structure as child of Map node (required for _ready and raycasting)
	map_node.add_child(structure_instance)

	# Set target_tile.structure (blocks other placement)
	target_tile.structure = structure_instance

	# Add structure to player's array and coordinate lookup
	structures.append(structure_instance)
	structures_by_coord[target_tile.get_coords()] = structure_instance

	# Connect destruction signal for victory/defeat tracking
	var game_node = get_parent()
	if is_instance_valid(game_node) and game_node.name == "Game":
		if structure_instance.has_signal("destroyed"):
			structure_instance.destroyed.connect(game_node._on_structure_destroyed)

	if instant:
		# Instant build: connect production signals and start immediately
		if structure_instance.produces_unit_type != "":
			if structure_instance.has_signal("unit_produced"):
				structure_instance.unit_produced.connect(_on_structure_unit_produced)
				structure_instance.start_production()
		print("Player %d instantly placed structure '%s' at %s. Remaining resources: %f" % [id, structure_key, target_tile.get_coords(), resources])
	else:
		# Ghost build: register with nearest base's construction queue
		structure_instance.resources_pending = structure_cost
		var base = find_closest_base(target_tile.get_coords())
		if is_instance_valid(base):
			base.add_to_construction_queue(structure_instance, "structure")
		else:
			push_warning("Player %d: No base found for construction queue." % id)
		print("Player %d placed ghost structure '%s' at %s. Queued for construction. Remaining resources: %f" % [id, structure_key, target_tile.get_coords(), resources])

	return true

func get_structure_at_coords(coords: Vector2i) -> Structure:
	"""
	Retrieves the Structure instance at the given grid coordinates, if owned by this player.
	"""
	return structures_by_coord.get(coords, null)

# --- Builder Dispatch ---

func find_closest_base(target_coords: Vector2i) -> Structure:
	"""
	Finds the closest base structure to the given coordinates.
	"""
	var closest_base: Structure = null
	var min_dist: float = 1e20
	for structure in structures:
		if not is_instance_valid(structure):
			continue
		var struct_config = GameData.STRUCTURE_TYPES.get(structure.structure_type)
		if not struct_config or struct_config.get("category") != "base":
			continue
		if structure.is_under_construction:
			continue
		var base_coords = structure.current_tile.get_coords()
		var dist = abs(base_coords.x - target_coords.x) + abs(base_coords.y - target_coords.y)
		if dist < min_dist:
			min_dist = dist
			closest_base = structure
	return closest_base

func register_road_construction(tiles: Array):
	"""
	Registers road tiles for construction.
	Each tile's road_resources_pending is already set by set_road_under_construction(cost).
	"""
	for road_tile in tiles:
		if not is_instance_valid(road_tile):
			continue

		# Set the owner so the base can identify who is building this road
		road_tile.road_owner_player_id = id

func _remove_builder(builder: Builder):
	"""
	Removes a builder from the tracking array.
	"""
	if builders.has(builder):
		builders.erase(builder)
