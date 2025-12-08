extends Node3D
class_name PlacementOverlay

# Constants for grid geometry and appearance
const Grid = preload("res://src/core/Grid.gd")
# Position the overlay slightly above the tile height (Y=0, plus a margin)
# Increased height to clear tile meshes, which might have thickness > 0.05.
const OVERLAY_HEIGHT: float = 0.2
# Green color with semi-transparency
const GREEN_TINT: Color = Color(0.0, 1.0, 0.0, 0.4) 

# --- Private Variables ---
var _grid: Grid = null
var _overlay_material: StandardMaterial3D = null
# Array to hold the generated MeshInstance3D nodes
var _active_meshes: Array[MeshInstance3D] = []

# --- Public Setup Methods ---

func set_grid(grid_instance: Grid) -> void:
	"""Initializes the Grid reference."""
	_grid = grid_instance

func _ready():
	# Initialize the shared material for all overlay meshes
	_overlay_material = StandardMaterial3D.new()
	_overlay_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_overlay_material.albedo_color = GREEN_TINT
	_overlay_material.cull_mode = BaseMaterial3D.CULL_DISABLED # Ensure double-sided rendering

# --- Mesh Generation Helpers ---

func _create_hex_mesh_instance() -> MeshInstance3D:
	"""Creates a new MeshInstance3D with a shared material and a simple flat Hexagonal Mesh."""
	
	var mesh_instance = MeshInstance3D.new()
	
	# Since Grid.gd uses HEX_SCALE: 0.6 and the tile spacing is derived from sqrt(3) * 0.57735,
	# using a PlaneMesh scaled to fit the hex footprint is the simplest approach.
	# The XZ dimensions of the hex grid cell are roughly X_SPACING (1.732 * 0.57735 = ~1.0) 
	# and Z_SPACING (~0.866). We scale the PlaneMesh (default 1x1) to match.
	
	# Dimensions of the Hex footprint are roughly: 
	# Width (X): Grid.X_SPACING (approx 1.0)
	# Depth (Z): 2.0 * Grid.HEX_SCALE (2 * 0.6 = 1.2)
	# However, since the plane is meant to sit directly on the ground tile, 
	# we should use the dimensions defined by the grid spacing constants.
	# Given Grid.X_SPACING and Grid.Z_SPACING, we can approximate the coverage area.
	
	# Assuming a normalized hex width of 1.0 (X_SPACING) and height of 0.866 * 2 (Z_SPACING * 2 / 1.5).
	# A simple PlaneMesh scaled to X=X_SPACING, Z=X_SPACING for coverage:
	
	var hex_width = Grid.X_SPACING * 0.95
	var hex_depth = Grid.X_SPACING * 0.95 # Approximate square coverage for simplicity
	
	var mesh = PlaneMesh.new()
	mesh.size = Vector2(hex_width, hex_depth)
	
	mesh_instance.mesh = mesh
	mesh_instance.set_surface_override_material(0, _overlay_material)
	add_child(mesh_instance)
	_active_meshes.append(mesh_instance)
	
	return mesh_instance

# --- Public Methods ---

func show_reachable(tiles: Array[Vector2i]):
	"""
	Creates green semi-transparent meshes over the given tiles.
	
	Arguments:
	- tiles (Array[Vector2i]): Array of grid coordinates to highlight.
	"""
	if _grid == null:
		push_error("PlacementOverlay: Grid reference is null.")
		return

	clear() # Clear existing meshes before showing new ones

	for coords in tiles:
		var world_pos = _grid.hex_to_world(coords.x, coords.y)
		
		# Only proceed if the coordinate is valid and world position is found (not Vector3.ZERO)
		if world_pos != Vector3.ZERO:
			var mesh_instance = _create_hex_mesh_instance()
			
			# Position the overlay slightly above the tile center's height
			mesh_instance.global_position = world_pos + Vector3(0, OVERLAY_HEIGHT, 0)
			
			# Orient the plane to be flat (default PlaneMesh is XZ plane)
			# No rotation needed, just position adjustment.


func show_neighbors(base_coord: Vector2i):
	"""
	Shows overlay for the 6 neighbor tiles of a base (for improvements).
	
	Arguments:
	- base_coord (Vector2i): The grid coordinates of the base structure.
	"""
	if _grid == null:
		push_error("PlacementOverlay: Grid reference is null.")
		return
		
	clear() # Clear existing meshes before showing new ones
	
	var base_tile = _grid.get_tile_by_coords(base_coord)
	
	if base_tile == null:
		push_warning("PlacementOverlay: Base tile not found for coordinates %s." % base_coord)
		return

	# Use the pre-calculated neighbors array on the Tile object
	for neighbor_tile in base_tile.neighbors:
		var coords = neighbor_tile.get_coords()
		var world_pos = neighbor_tile.world_pos # Tile object already stores world_pos
		
		# We assume `world_pos` is valid since it comes from a registered tile.
		var mesh_instance = _create_hex_mesh_instance()
		
		# Position the overlay slightly above the tile center's height
		mesh_instance.global_position = world_pos + Vector3(0, OVERLAY_HEIGHT, 0)
		

func clear():
	"""Removes all overlay meshes."""
	for mesh in _active_meshes:
		if is_instance_valid(mesh):
			mesh.queue_free()
	
	_active_meshes.clear()
