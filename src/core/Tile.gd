class_name Tile

# Godot's built-in infinity constant for floats
const INF: float = 1e20 

# Grid coordinates
var x: int
var z: int

# World position of the tile center
var world_pos: Vector3

# The actual Node3D instance representing the tile in the scene tree (StaticBody3D)
var node: Node3D

# Gameplay properties
var walkable: bool = true
var cost: float = 1.0

# A list of neighboring Tile objects, assigned after map generation
var neighbors: Array[Tile] = []

# Pathfinding properties (used for flow field generation/pathfinding)
# Flow field data is now stored in the FlowField object itself for multi-player support.

func get_coords() -> Vector2i:
	return Vector2i(x, z)