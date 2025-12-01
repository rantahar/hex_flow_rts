extends Node3D

class_name MapGenerator

# 1. Exports
@export var tile_mesh: Mesh # Mesh to instance for each tile
@export var map_width: int = 20
@export var map_height: int = 20
@export var hex_scale: float = 0.6

# Constants for Pointy-Topped Hex Grid (assuming radius R=1)
const X_SPACING: float = 1.732*0.57735 # sqrt(3) 
const Z_SPACING: float = 1.5*0.57735   # 3/2 1.732

func _ready():
	generate_map()

# 2. Generation Logic (using individual Node Instantiation)
func generate_map():
	if not tile_mesh:
		push_error("Tile Mesh is not set.")
		return
	
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
			tile_mesh_instance.mesh = tile_mesh
			
			# Scale: Set node.scale
			tile_mesh_instance.scale = Vector3.ONE * hex_scale
			
			# Rotation Fix: Set node.rotation_degrees.y = 90 (or similar)
			tile_mesh_instance.rotation_degrees.y = 0.0
			
			tile_root.add_child(tile_mesh_instance)
			
			add_child(tile_root)
