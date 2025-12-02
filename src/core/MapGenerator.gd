extends Node3D

class_name MapGenerator

const Tile = preload("res://src/core/Tile.gd")

# 1. Exports
@export var grass_mesh: Mesh
@export var dirt_mesh: Mesh
@export var stone_mesh: Mesh
@export var water_mesh: Mesh
@export var map_width: int = 20
@export var map_height: int = 20
@export var hex_scale: float = 0.6

var generated_tiles: Dictionary = {}

# Constants for Pointy-Topped Hex Grid (assuming radius R=1)
const X_SPACING: float = 1.732*0.57735 # sqrt(3)
const Z_SPACING: float = 1.5*0.57735   # 3/2 1.732

# 2. Generation Logic (using individual Node Instantiation)
func generate_map():
	var tile_meshes = [grass_mesh, dirt_mesh, stone_mesh, water_mesh]
	tile_meshes.erase(null) # Remove null entries if user hasn't set all types
	
	if tile_meshes.is_empty():
		push_error("No tile meshes are set.")
		return
		
	generated_tiles.clear() # Clear previously generated tile data
	
	# Clear existing children
	for child in get_children():
		child.queue_free()

	for z in range(map_height):
		for x in range(map_width):
			
			# Hex position calculation (Odd-R offset logic)
			var pos_x = float(x) * X_SPACING * hex_scale
			var pos_z = float(z) * Z_SPACING * hex_scale
			
			# Apply Offset: If z (row) is odd, add half-spacing to pos_x
			if z % 2 != 0:
				pos_x += (X_SPACING * hex_scale) / 2.0
				
			var position = Vector3(pos_x, 0, pos_z)
			
			# 3. Optimization: Create a StaticBody3D child for the tile
			var tile_root = StaticBody3D.new()
			tile_root.name = "Hex_%d_%d" % [x, z]
			tile_root.position = position
			
			# Instantiate MeshInstance3D
			var tile_mesh_instance = MeshInstance3D.new()
			
			# Mesh: Set node.mesh = tile_mesh
			var selected_mesh = tile_meshes.pick_random()
			tile_mesh_instance.mesh = selected_mesh
			
			# Scale: Set node.scale
			tile_mesh_instance.scale = Vector3.ONE * hex_scale
			
			# Rotation Fix: Set node.rotation_degrees.y = 90 (or similar)
			tile_mesh_instance.rotation_degrees.y = 0.0
			
			# Add collision shape based on mesh geometry
			tile_mesh_instance.create_trimesh_collision() # Requirement 1: Trimesh collision
			
			tile_root.add_child(tile_mesh_instance)
			
			add_child(tile_root)
			
			# Requirement 2: Store tile reference
			var tile_data = Tile.new()
			tile_data.x = x
			tile_data.z = z
			tile_data.world_pos = position
			
			# Set infinite cost for water tiles
			if selected_mesh == water_mesh:
				tile_data.walkable = false
				tile_data.cost = Tile.INF # Tile.INF defined in Tile.gd
				
			tile_data.node = tile_root # Use the StaticBody3D (tile_root) as the node reference for lookup
			
			var coords = Vector2i(x, z)
			generated_tiles[coords] = tile_data

func get_tiles() -> Dictionary:
	return generated_tiles
