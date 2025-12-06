class_name Tile

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
# Stores Unit references in slots (null if slot is free)
var occupied_slots: Array = [null, null, null, null, null, null]

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
	"""
	Returns the grid coordinates (x, z) of the tile.

	Returns:
	- Vector2i: The coordinates of the tile on the grid.
	"""
	return Vector2i(x, z)

# Finds and returns the index of the first available formation slot, and registers the unit in it.
func claim_formation_slot(unit: Unit) -> int:
	"""
	Attempts to find and claim the first available formation slot on this tile for a given unit.

	Arguments:
	- unit (Unit): The unit instance attempting to claim a slot.

	Returns:
	- int: The index of the claimed slot (0-5), or -1 if all slots are occupied.
	"""
	for i in range(occupied_slots.size()):
		if occupied_slots[i] == null:
			occupied_slots[i] = unit # Register the unit instance
			return i
	return -1 # Full

# Releases a slot by setting it to null.
func release_formation_slot(slot_index: int):
	"""
	Releases a specific formation slot on the tile, making it available for other units.

	Arguments:
	- slot_index (int): The index of the slot to release.
	"""
	if slot_index != -1 and slot_index >= 0 and slot_index < occupied_slots.size():
		occupied_slots[slot_index] = null

# Checks if this tile contains any units belonging to a different player.
func has_enemy_units(player_id: int) -> bool:
	"""
	Checks if there are any units occupying this tile that belong to a different player.

	Arguments:
	- player_id (int): The ID of the player checking for enemies.

	Returns:
	- bool: True if an enemy unit is present, false otherwise.
	"""
	for unit_reference in occupied_slots:
		if unit_reference != null:
			# Safety check: ensure unit_reference is a valid instance before accessing player_id
			if is_instance_valid(unit_reference) and unit_reference.player_id != player_id:
				return true
			elif not is_instance_valid(unit_reference):
				push_warning("Tile (%d, %d) occupied_slots contains an invalid unit reference." % [x, z])
	return false

func is_formation_full() -> bool:
	"""
	Checks if all formation slots on this tile are currently occupied by units.

	Returns:
	- bool: True if all slots are full, false otherwise.
	"""
	for slot in occupied_slots:
		if slot == null:
			return false
	return true
