class_name Tile
extends CSGMesh3D

# Preloads needed for type hinting and access to constants
const Grid = preload("res://src/core/Grid.gd")
const Structure = preload("res://src/core/Structure.gd")
const Unit = preload("res://src/core/Unit.gd")
const GameConfig = preload("res://data/game_config.gd")

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


# Gameplay properties
var walkable: bool = true
var cost: float = 1.0

# Reference to the Structure built on this tile (null if free)
var structure: Structure = null

# Reference to an optional child node representing a drill hole
@onready var hole_node: Node3D = $Hole

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
	- int: The index of the claimed slot (0-5), or -1 if all slots are occupied or a structure is present.
	"""
	# Structures block all formation slots
	if structure != null:
		return -1
		
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

# Checks if this tile should be considered a target for flow field calculation.
# This only checks for enemy structures and units.
func is_flow_target(player_id: int) -> bool:
	"""
	Returns true if the tile contains an enemy unit or an enemy structure,
	making it a military target.
	"""
	# 1. Check for enemy units
	if has_enemy_units(player_id):
		return true
		
	# 2. Check for enemy structure
	if structure != null and is_instance_valid(structure) and structure.player_id != player_id:
		return true
		
	return false

func set_overlay_tint(color: Color):
	"""
	Sets a tint color override on the tile's primary mesh to indicate selection/hover state.
	Assumes the tile's node (a CSGMesh3D) holds the mesh directly.
	
	Arguments:
	- color (Color): The color to tint the tile with (including alpha).
	"""
	if not is_instance_valid(self):
		push_error("Tile (%d, %d): Instance is invalid, cannot set tint." % [x, z])
		return
		
	# self is the CSGMesh3D root node
	# Use material_overlay to blend on top of existing materials
	if not is_instance_valid(material_overlay):
		material_overlay = StandardMaterial3D.new()
		material_overlay.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material_overlay.cull_mode = BaseMaterial3D.CULL_DISABLED
	material_overlay.albedo_color = color

func set_tile_visibility(is_visible: bool):
	"""
	Sets the visibility of the tile (the root node).
	"""
	if is_instance_valid(self):
		visible = is_visible

func set_hole_visibility(is_visible: bool):
	"""
	Sets the visibility of the 'Hole' child node.
	"""
	if is_instance_valid(hole_node):
		hole_node.visible = is_visible

# Calculates the flow field cost for a unit of player_id attempting to move onto this tile.
func get_flow_cost(player_id: int) -> float:
	"""
	Calculates the movement cost of this tile for a given player ID, factoring in
	walkability, base terrain cost, friendly structure blocking, and friendly unit density.
	
	Returns:
	- float: The movement cost, or INF if blocked. Returns 0.0 if it's an attack target.
	"""
	
	# 1. Immediate Target Check (Cost 0.0)
	# If this tile is a flow target (enemy unit/structure), movement cost is 0.0 to encourage flow towards it.
	if is_flow_target(player_id):
		return 0.0

	# 2. Blocked Check (Cost INF)
	if not walkable:
		return INF
	
	# Friendly structures block all movement onto the tile
	if structure != null and is_instance_valid(structure) and structure.player_id == player_id:
		return INF
			
	# 3. Base Terrain Cost + Density Cost
	
	var total_cost: float = cost
	var density_cost: float = 0.0
	
	# Calculate density cost based on friendly units on the tile.
	# Note: Only units currently NOT being processed by this flow field should be counted,
	# but for simplicity, we count all friendly units and rely on combat checks elsewhere.
	var friendly_unit_count: int = 0
	for unit in occupied_slots:
		if unit != null and is_instance_valid(unit) and unit.player_id == player_id:
			friendly_unit_count += 1
	
	if friendly_unit_count > 0:
		density_cost = friendly_unit_count * GameConfig.DENSITY_COST_MULTIPLIER
		
	total_cost += density_cost
	
	return total_cost

func is_buildable_terrain() -> bool:
	"""
	Checks if the tile's underlying terrain type allows placing a structure.
	For simplicity, currently requires the tile to be walkable.
	"""
	return walkable

func _ready():
	# Ensure the Hole node is initially hidden and non-pickable,
	# as it shouldn't interfere with tile clicks/raycasts.
	if is_instance_valid(hole_node):
		hole_node.visible = false
		
		# Ensure the visual children of the hole node are not pickable,
		# as the hole node itself may not have the input_ray_pickable property.
		for child in hole_node.get_children():
			if child.has_method("set_input_ray_pickable"):
				child.set_input_ray_pickable(false)
