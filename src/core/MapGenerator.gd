extends Node3D

class_name MapGenerator

const GameData = preload("res://data/game_data.gd")
const GameConfig = preload("res://data/game_config.gd")
const TILE_SCENE = preload("res://src/core/tile.tscn")


var map_width: int = GameData.MAP_WIDTH
var map_height: int = GameData.MAP_HEIGHT

@onready var grid: Grid = get_parent().get_node("Grid")

var generated_tiles: Dictionary = {}

# Constants for Pointy-Topped Hex Grid (assuming radius R=1)
# 2. Generation Logic (using individual Node Instantiation)
func generate_map():
	"""
	Generates the entire hexagonal map grid by iterating through coordinates (x, z).
	For each coordinate, it instantiates a visual tile (StaticBody3D + MeshInstance3D),
	applies a random weighted tile type, sets up collision, and creates the Tile data object.
	"""
	generated_tiles.clear() # Clear previously generated tile data

	# Clear existing children
	for child in get_children():
		child.queue_free()

	for z in range(map_height):
		for x in range(map_width):

			# Hex position calculation (Odd-R offset logic)
			var pos_x = float(x) * Grid.X_SPACING * GameConfig.HEX_SCALE
			var pos_z = float(z) * Grid.Z_SPACING * GameConfig.HEX_SCALE

			# Apply Offset: If z (row) is odd, add half-spacing to pos_x
			if z % 2 != 0:
				pos_x += (Grid.X_SPACING * GameConfig.HEX_SCALE) / 2.0

			var position = Vector3(pos_x, 0, pos_z)

			# 3. Instantiate Tile Scene (CSGMesh3D root)
			var tile_root = TILE_SCENE.instantiate()
			tile_root.name = "Hex_%d_%d" % [x, z]
			tile_root.position = position

			# Mesh: Select random tile type and load resource
			var selected_tile_key = _get_weighted_random_tile_key()
			if selected_tile_key.is_empty():
				push_error("Failed to select a tile type.")
				continue
			var tile_def = GameData.TILES[selected_tile_key]

			var selected_mesh: Mesh = load(tile_def.mesh_path)

			if not selected_mesh:
				push_error("Failed to load Mesh resource: %s. Skipping tile." % tile_def.mesh_path)
				continue

			# Set mesh on the root node (CSGMesh3D)
			tile_root.mesh = selected_mesh

			# Scale: Set node.scale
			tile_root.scale = Vector3.ONE * GameConfig.HEX_SCALE

			# Rotation Fix (Keep for consistency)
			tile_root.rotation_degrees.y = 0.0

			# Add to the scene tree (parent MapGenerator)
			add_child(tile_root)

			# Collision is assumed to be handled by the CSGMesh3D properties in the scene.

			# Requirement 2: Store tile reference
			# Since tile_root is a CSGMesh3D with Tile.gd attached, it is the Tile object itself.
			var tile_data: Tile = tile_root
			tile_data.x = x
			tile_data.z = z
			tile_data.world_pos = position

			# Apply tile data properties
			tile_data.walkable = tile_def.walkable
			tile_data.cost = tile_def.walk_cost

			var coords = Vector2i(x, z)
			generated_tiles[coords] = tile_data

	# After all tiles are added to scene tree, update their Y positions to match actual terrain height
	_update_tile_heights()

func _update_tile_heights() -> void:
	"""
	After tiles are added to the scene tree, raycasts to find the actual terrain height
	at each tile's center position and updates the world_pos.y accordingly.
	"""
	var map_node = get_parent()
	if not is_instance_valid(map_node):
		push_error("MapGenerator: Could not find parent Map node")
		return

	for coords in generated_tiles:
		var tile: Tile = generated_tiles[coords]
		if not is_instance_valid(tile):
			continue

		# Raycast to find actual terrain height at this tile's XZ position
		var planar_pos = Vector3(tile.world_pos.x, 0, tile.world_pos.z)
		var terrain_height = map_node.get_height_at_world_pos(planar_pos)

		# Update the tile's world_pos with the correct Y coordinate
		tile.world_pos.y = terrain_height

func get_tiles() -> Dictionary:
	"""
	Returns the dictionary of generated Tile objects keyed by their coordinates.

	Returns:
	- Dictionary: {Vector2i: Tile} mapping.
	"""
	return generated_tiles

# Helper function to select a tile key based on defined weights.
func _get_weighted_random_tile_key() -> String:
	"""
	Selects a tile type key from GameData.TILES using weighted random sampling.
	Higher weight values increase the probability of selection.

	Returns:
	- String: The key of the randomly selected tile type, or "" on error.
	"""
	var weighted_list = []
	var total_weight = 0

	for key in GameData.TILES:
		var weight = GameData.TILES[key].get("weight", 1) # Default weight of 1 if not specified
		total_weight += weight
		for _i in range(weight):
			weighted_list.append(key)

	if weighted_list.is_empty():
		push_error("Weighted tile list is empty.")
		return ""

	# Randomly pick an element from the weighted list
	return weighted_list.pick_random()
