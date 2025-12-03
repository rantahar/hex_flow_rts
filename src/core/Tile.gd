class_name Tile

const Grid = preload("res://src/core/Grid.gd")
const FORMATION_RADIUS: float = Grid.HEX_SCALE * 0.3

# 6 positions in a radial hex pattern around tile center (radius ~0.3 * HEX_SCALE)
# Positions are Vector2 (X, Z offsets from tile center)
const FORMATION_POSITIONS: Array[Vector2] = [
	Vector2(FORMATION_RADIUS, 0.0), # 0 deg (E)
	Vector2(FORMATION_RADIUS * 0.5, FORMATION_RADIUS * 0.866025), # 60 deg (NE)
	Vector2(FORMATION_RADIUS * -0.5, FORMATION_RADIUS * 0.866025), # 120 deg (NW)
	Vector2(-FORMATION_RADIUS, 0.0), # 180 deg (W)
	Vector2(FORMATION_RADIUS * -0.5, FORMATION_RADIUS * -0.866025), # 240 deg (SW)
	Vector2(FORMATION_RADIUS * 0.5, FORMATION_RADIUS * -0.866025), # 300 deg (SE)
]
var occupied_slots: Array[bool] = [false, false, false, false, false, false]

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


func get_coords() -> Vector2i:
	return Vector2i(x, z)

func claim_formation_slot() -> int:
	for i in range(FORMATION_POSITIONS.size()):
		if not occupied_slots[i]:
			occupied_slots[i] = true
			return i
	return -1 # Full

func release_formation_slot(slot_index: int):
	if slot_index != -1 and slot_index >= 0 and slot_index < occupied_slots.size():
		occupied_slots[slot_index] = false
