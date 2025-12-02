extends Node3D

# Export: player_id (int)
@export var id: int # Player configuration (replacing player_id)
@export var unit_mesh: Mesh # Mesh resource for the unit model

# Required for Game.gd initialization logic
var color: Color = Color.WHITE
var target: Vector2i = Vector2i.ZERO
var flow_field = null # Assumes FlowField is globally available or handled by Game.gd
var units: Array = []
var resources: int = 0

# We assume Unit.gd is used directly as the unit's class/resource definition.

const HEX_SCALE = 0.6
# X_SPACING = sqrt(3) * 0.57735 approx 1.732 * 0.57735 = 1.0
# Z_SPACING = 1.5 * 0.57735 approx 0.866
const X_SPACING = 1.73205 * 0.57735
const Z_SPACING = 1.5 * 0.57735

# Method: spawn_unit(hex_x: int, hex_z: int, map_node: Node3D) -> Unit
func spawn_unit(hex_x: int, hex_z: int, map_node: Node3D):
    if not map_node:
        push_error("Map node required for unit spawning.")
        return null

    # 1. Calculate world position from hex coords using explicit spacing
    var pos_x = float(hex_x) * X_SPACING * HEX_SCALE
    var pos_z = float(hex_z) * Z_SPACING * HEX_SCALE
    
    # Apply Odd-R offset (if z % 2 != 0, add X_SPACING*HEX_SCALE/2 to pos_x)
    if hex_z % 2 != 0:
        pos_x += X_SPACING * HEX_SCALE / 2.0
        
    var world_x = pos_x
    var world_z = pos_z

    # 2. Instantiate Unit
    var unit = Unit.new()
    
    # 3. Initialize Unit
    unit.mesh = unit_mesh
    unit.player_id = id
    # Position unit at (world_x, 0.5, world_z)
    unit.initialize(hex_x, hex_z, world_x, world_z)
    
    # 4. Add unit as child of map_node
    map_node.add_child(unit)
    
    return unit
