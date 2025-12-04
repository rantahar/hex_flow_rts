class_name Player
extends Node3D

# Exported player ID.
@export var id: int
const GameData = preload("res://data/game_data.gd")

# Required for Game.gd initialization logic
var color: Color = Color.WHITE
var target: Vector2i = Vector2i.ZERO
var flow_field = null # Assumes FlowField is globally available or handled by Game.gd
var units: Array = []
var resources: int = 0
var spawn_tile: Tile
const SPAWN_INTERVAL: float = 1
var spawn_timer: float = SPAWN_INTERVAL

func _process(delta: float):
	if not spawn_tile:
		return
		
	spawn_timer += delta
	
	if spawn_timer >= SPAWN_INTERVAL:
		spawn_timer -= SPAWN_INTERVAL
		
		# NOTE: We need a reference to the Grid/Map node to spawn.
		# Assuming the parent of Player is Game, and Game has a reference to Map/Grid.
		# Since Player is a Node3D in the scene, and units are children of the Map, 
		# we will rely on Game.gd to pass the map reference. 
		# For now, let's assume `get_parent().get_node("Map")` is available and safe,
		# although a better practice might be passing a reference during initialization.
		# Looking at spawn_unit's signature, it requires `map_node`.
		# Since `spawn_unit` is currently being called without args in Game.gd,
		# we need to ensure the map node is accessible, or update Game.gd later to expose it.
		# Given the original `spawn_unit` signature takes `map_node`, 
		# it seems safer to assume `map_node` should be retrieved or stored.
		# Let's adjust spawn_unit to handle optional hex_x, hex_z, 
		# and assume map_node is passed in from Game, or retrieve it here.
		
		# Let's assume we can get the Map from the Game node (our parent).
		var game_node = get_parent()
		if game_node and game_node.has_node("Map"):
			var map_node = game_node.get_node("Map")
			# Passing default -1 values to trigger spawn_tile usage in spawn_unit()
			spawn_unit(-1, -1, map_node)


# We assume Unit.gd is used directly as the unit's class/resource definition.


# Method: spawn_unit(hex_x: int, hex_z: int, map_node: Node3D) -> Unit
func spawn_unit(hex_x: int = -1, hex_z: int = -1, map_node: Node3D = null, unit_type: String = "infantry"):
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
