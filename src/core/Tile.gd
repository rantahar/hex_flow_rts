class_name Tile
extends CSGMesh3D

# Preloads needed for type hinting and access to constants
const Grid = preload("res://src/core/Grid.gd")
const Structure = preload("res://src/core/Structure.gd")
const Unit = preload("res://src/core/Unit.gd")
const GameConfig = preload("res://data/game_config.gd")
const GameData = preload("res://data/game_data.gd")

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
# Stores Builder references passing through or stationed on this tile
var builder_occupants: Array = []

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

# Road properties (roads are neutral when complete - usable by all players)
var has_road: bool = false
var road_hp: float = 0.0
var road_visual: Node3D = null
var road_under_construction: bool = false
var road_resources_pending: float = 0.0
var road_resources_in_transit: float = 0.0  # Resources being carried by builders already sent
var road_builders: Array[int] = []  # Player IDs building this road

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
func claim_formation_slot(unit: Node3D) -> int:
	"""
	Attempts to find and claim the first available formation slot on this tile for a given unit or builder.

	Arguments:
	- unit (Node3D): The unit or builder instance attempting to claim a slot.

	Returns:
	- int: The index of the claimed slot (0-5), or -1 if all slots are occupied or a structure is present.
	"""
	# Completed structures block all formation slots (under-construction ones allow builders through)
	if structure != null and not structure.is_under_construction:
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

func register_builder(builder: Node3D) -> void:
	builder_occupants.append(builder)

func unregister_builder(builder: Node3D) -> void:
	builder_occupants.erase(builder)

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

func set_road_under_construction(segment_cost: float = 0.0):
	road_under_construction = true
	road_resources_pending = segment_cost
	_update_road_ghost_visual()

func complete_road_construction():
	road_under_construction = false
	road_builders.clear()
	set_road()

func set_road():
	has_road = true
	road_under_construction = false
	road_hp = GameData.ROAD_CONFIG.max_hp
	_update_road_visual()
	# Also update neighbors so they draw connections to this tile
	for neighbor in neighbors:
		if is_instance_valid(neighbor) and neighbor.has_road:
			neighbor._update_road_visual()

func clear_road():
	has_road = false
	road_hp = 0.0
	_remove_road_visual()
	# Update neighbors to remove connections to this tile
	for neighbor in neighbors:
		if is_instance_valid(neighbor) and neighbor.has_road:
			neighbor._update_road_visual()

func damage_road(amount: float):
	if not has_road:
		return
	road_hp -= amount
	if road_hp <= 0:
		clear_road()

func _remove_road_visual():
	if is_instance_valid(road_visual):
		road_visual.queue_free()
		road_visual = null

func _update_road_ghost_visual():
	_remove_road_visual()
	road_visual = Node3D.new()
	road_visual.name = "RoadGhostVisual"
	add_child(road_visual)

	var ghost_mat = StandardMaterial3D.new()
	ghost_mat.albedo_color = Color(0.55, 0.35, 0.15, 0.35)
	ghost_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ghost_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	var road_config = GameData.ROAD_CONFIG
	var line_w: float = road_config.line_width
	var line_h: float = road_config.line_height
	var y_off: float = road_config.visual_y_offset

	var center_ground_y = _get_ground_y(world_pos.x, world_pos.z)
	var center_local_y = center_ground_y - global_position.y + y_off

	var center_box = BoxMesh.new()
	center_box.size = Vector3(line_w * 1.5, line_h, line_w * 1.5)
	var center_mesh = MeshInstance3D.new()
	center_mesh.mesh = center_box
	center_mesh.material_override = ghost_mat
	center_mesh.position = Vector3(0.0, center_local_y, 0.0)
	road_visual.add_child(center_mesh)

func _get_ground_y(world_x: float, world_z: float) -> float:
	# Tile -> Grid -> Map
	var grid_node = get_parent()
	if is_instance_valid(grid_node):
		var map_node = grid_node.get_parent()
		if is_instance_valid(map_node) and map_node.has_method("get_height_at_world_pos"):
			return map_node.get_height_at_world_pos(Vector3(world_x, 0.0, world_z))
	return 0.0

func _update_road_visual():
	_remove_road_visual()
	if not has_road:
		return

	road_visual = Node3D.new()
	road_visual.name = "RoadVisual"
	add_child(road_visual)

	var road_mat = StandardMaterial3D.new()
	road_mat.albedo_color = Color(0.55, 0.35, 0.15)
	road_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	var road_config = GameData.ROAD_CONFIG
	var line_w: float = road_config.line_width
	var line_h: float = road_config.line_height
	var y_off: float = road_config.visual_y_offset

	# Raycast at tile center for ground height
	var center_ground_y = _get_ground_y(world_pos.x, world_pos.z)
	var center_local_y = center_ground_y - global_position.y + y_off

	# Center dot so isolated/endpoint road tiles are visible
	var center_box = BoxMesh.new()
	center_box.size = Vector3(line_w * 1.5, line_h, line_w * 1.5)
	var center_mesh = MeshInstance3D.new()
	center_mesh.mesh = center_box
	center_mesh.material_override = road_mat
	center_mesh.position = Vector3(0.0, center_local_y, 0.0)
	road_visual.add_child(center_mesh)

	# Draw a line from center toward each neighboring road tile's shared edge
	for neighbor in neighbors:
		if not is_instance_valid(neighbor) or not neighbor.has_road:
			continue

		# Horizontal direction to neighbor
		var dir_xz = Vector3(neighbor.world_pos.x - world_pos.x, 0.0, neighbor.world_pos.z - world_pos.z)
		var horiz_len = dir_xz.length()
		if horiz_len < 0.001:
			continue

		var half_len = horiz_len * 0.5
		var dir_norm = dir_xz.normalized()

		# Raycast at edge midpoint (halfway to neighbor) for ground height
		var edge_world_x = world_pos.x + dir_norm.x * half_len
		var edge_world_z = world_pos.z + dir_norm.z * half_len
		var edge_ground_y = _get_ground_y(edge_world_x, edge_world_z)
		var edge_local_y = edge_ground_y - global_position.y + y_off

		# Start (center) and end (edge midpoint) in local space
		var start_pos = Vector3(0.0, center_local_y, 0.0)
		var end_pos = Vector3(dir_norm.x * half_len, edge_local_y, dir_norm.z * half_len)

		var seg_dir = end_pos - start_pos
		var seg_length = seg_dir.length()
		if seg_length < 0.001:
			continue

		var box = BoxMesh.new()
		box.size = Vector3(line_w, line_h, seg_length)

		var line_mesh = MeshInstance3D.new()
		line_mesh.mesh = box
		line_mesh.material_override = road_mat

		# Position at segment midpoint
		line_mesh.position = (start_pos + end_pos) * 0.5

		# Orient: Y rotation for horizontal direction, X rotation for slope
		var seg_norm = seg_dir.normalized()
		line_mesh.rotation.y = atan2(seg_norm.x, seg_norm.z)
		var horiz_dist = Vector2(seg_norm.x, seg_norm.z).length()
		line_mesh.rotation.x = -atan2(seg_norm.y, horiz_dist)

		road_visual.add_child(line_mesh)

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

	# 2. Road Check - roads override walkability (bridges over water)
	# Roads under construction don't provide cost benefits yet
	if has_road and not road_under_construction:
		var base_cost: float = GameData.ROAD_CONFIG.road_tile_cost
		# Still check for friendly structure blocking on road tiles (under-construction allowed)
		if structure != null and is_instance_valid(structure) and structure.player_id == player_id and not structure.is_under_construction:
			return INF
		var total_road_cost: float = base_cost
		var road_friendly_count: int = 0
		for unit in occupied_slots:
			if unit != null and is_instance_valid(unit) and unit.player_id == player_id:
				road_friendly_count += 1
		if road_friendly_count > 0:
			total_road_cost += road_friendly_count * GameConfig.DENSITY_COST_MULTIPLIER
		return total_road_cost

	# 3. Blocked Check (Cost INF)
	if not walkable:
		return INF

	# Friendly structures are passable (no extra cost) - builders can move through them freely

	# 4. Base Terrain Cost + Density Cost

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

func get_road_resource_request() -> float:
	"""
	Returns how many resources are still needed for this road.
	Accounts for resources already in transit via builders.
	"""
	if not road_under_construction or road_resources_pending <= 0:
		return 0.0
	return maxf(0.0, road_resources_pending - road_resources_in_transit)

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
