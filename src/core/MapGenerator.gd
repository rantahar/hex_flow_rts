extends Node3D

class_name MapGenerator

const GameData = preload("res://data/game_data.gd")


var map_width: int = GameData.MAP_WIDTH
var map_height: int = GameData.MAP_HEIGHT
@export var hex_scale: float = 0.6

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
			var pos_x = float(x) * Grid.X_SPACING * hex_scale
			var pos_z = float(z) * Grid.Z_SPACING * hex_scale
			
			# Apply Offset: If z (row) is odd, add half-spacing to pos_x
			if z % 2 != 0:
				pos_x += (Grid.X_SPACING * hex_scale) / 2.0
				
			var position = Vector3(pos_x, 0, pos_z)
			
			# 3. Optimization: Create a StaticBody3D child for the tile
			var tile_root = StaticBody3D.new()
			tile_root.name = "Hex_%d_%d" % [x, z]
			tile_root.position = position
			
			# Instantiate MeshInstance3D
			var tile_mesh_instance = MeshInstance3D.new()
			
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
				
			tile_mesh_instance.mesh = selected_mesh
			
			# Scale: Set node.scale
			tile_mesh_instance.scale = Vector3.ONE * hex_scale
			
			# Rotation Fix: Set node.rotation_degrees.y = 90 (or similar)
			tile_mesh_instance.rotation_degrees.y = 0.0
			
			# Add visual node to the StaticBody3D
			tile_root.add_child(tile_mesh_instance)
			
			# Add StaticBody3D to the scene tree (parent MapGenerator)
			add_child(tile_root)
			
			# Add collision shape based on mesh geometry
			tile_mesh_instance.create_trimesh_collision() # Requirement 1: Trimesh collision
			
			# Requirement 2: Store tile reference
			var tile_data = Tile.new()
			tile_data.x = x
			tile_data.z = z
			tile_data.world_pos = position
			
			# Apply tile data properties
			tile_data.walkable = tile_def.walkable
			tile_data.cost = tile_def.walk_cost
			
			tile_data.node = tile_root # Use the StaticBody3D (tile_root) as the node reference for lookup
			
			var coords = Vector2i(x, z)
			generated_tiles[coords] = tile_data

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
