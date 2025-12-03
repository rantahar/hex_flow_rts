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

# We assume Unit.gd is used directly as the unit's class/resource definition.


# Method: spawn_unit(hex_x: int, hex_z: int, map_node: Node3D) -> Unit
func spawn_unit(hex_x: int, hex_z: int, map_node: Node3D, unit_type: String = "infantry"):
    if not map_node:
        push_error("Player.spawn_unit: Map node is null")
        return null
    
    # Add bounds check using Grid reference
    var grid = map_node.get_node_or_null("Grid")
    if not grid:
        push_error("Player.spawn_unit: Could not find Grid node in map")
        return null
    
    var coords = Vector2i(hex_x, hex_z)
    if not grid.is_valid_coords(coords):
        push_error("Player.spawn_unit: Invalid coordinates (%d, %d) - tile does not exist" % [hex_x, hex_z])
        return null

    # 1. Calculate world position from hex coords using explicit spacing
    var pos_x = float(hex_x) * Grid.X_SPACING * Grid.HEX_SCALE
    var pos_z = float(hex_z) * Grid.Z_SPACING * Grid.HEX_SCALE
    
    # Apply Odd-R offset (if z % 2 != 0, add X_SPACING*HEX_SCALE/2 to pos_x)
    if hex_z % 2 != 0:
        pos_x += Grid.X_SPACING * Grid.HEX_SCALE / 2.0
        
    var world_x = pos_x
    var world_z = pos_z

    # 2. Instantiate Unit
    var world_pos = Vector3(world_x, 0.0, world_z)
    
    # Use the specified unit configuration dictionary
    if not GameData.UNIT_TYPES.has(unit_type):
        push_error("Player.spawn_unit: Invalid unit type: %s" % unit_type)
        return null
        
    var unit_config = GameData.UNIT_TYPES[unit_type]
    var unit = Unit.new(unit_config, id, hex_x, hex_z, world_pos)
    
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
