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

			# CSGMesh3D root: thin manifold hex prism for collision only (invisible)
			var hex_prism = CylinderMesh.new()
			hex_prism.radial_segments = 6
			hex_prism.rings = 1
			hex_prism.top_radius = 0.5
			hex_prism.bottom_radius = 0.5
			hex_prism.height = 0.15
			tile_root.mesh = hex_prism
			tile_root.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var invis_mat = StandardMaterial3D.new()
			invis_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			invis_mat.albedo_color = Color(0, 0, 0, 0)
			invis_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			tile_root.material_override = invis_mat

			# MeshInstance3D child: actual visual OBJ (supports any mesh topology)
			var visual = MeshInstance3D.new()
			visual.name = "Visual"
			visual.mesh = selected_mesh
			tile_root.add_child(visual)

			# Debug: print mesh AABB for diagnosis
			var aabb = selected_mesh.get_aabb()
			print("[MapGen] tile=%s key=%s mesh=%s aabb=%s" % [tile_root.name, selected_tile_key, tile_def.mesh_path, aabb])

			# Scale: Set node.scale
			tile_root.scale = Vector3.ONE * GameConfig.HEX_SCALE * 0.9

			# Rotation Fix (Keep for consistency)
			tile_root.rotation_degrees.y = 0.0

			# Add to the scene tree (parent MapGenerator)
			add_child(tile_root)

			# Debug: post-add state (global_* require being in the scene tree)
			print("[MapGen]   grid=(%d,%d) local_pos=%s global_pos=%s scale=%s rot_deg=%s visible=%s" % [
				x, z,
				tile_root.position,
				tile_root.global_position,
				tile_root.scale,
				tile_root.rotation_degrees,
				tile_root.visible,
			])
			# World-space AABB after scale (approximation: local aabb scaled)
			var world_aabb_min = tile_root.global_position + aabb.position * tile_root.scale
			var world_aabb_max = world_aabb_min + aabb.size * tile_root.scale
			print("[MapGen]   world_aabb approx min=%s max=%s" % [world_aabb_min, world_aabb_max])

			# Requirement 2: Store tile reference
			# Since tile_root is a CSGMesh3D with Tile.gd attached, it is the Tile object itself.
			var tile_data: Tile = tile_root
			tile_data.x = x
			tile_data.z = z
			tile_data.world_pos = position

			# Apply tile data properties
			tile_data.walkable = tile_def.walkable
			tile_data.cost = tile_def.walk_cost
			tile_data.buildable = tile_def.buildable

			var coords = Vector2i(x, z)
			generated_tiles[coords] = tile_data

	# After all tiles are added to scene tree, update their Y positions to match actual terrain height
	_update_tile_heights()
	# Deferred check: CSG bakes on the next frame, so check after that
	call_deferred("_debug_check_csg_bakes")

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

func _debug_check_csg_bakes() -> void:
	for coords in generated_tiles:
		var tile: Tile = generated_tiles[coords]
		if not is_instance_valid(tile):
			continue
		var meshes = tile.get_meshes()
		var mesh_path = tile.mesh.resource_path if tile.mesh else "null"
		if meshes.is_empty():
			print("[MapGen CSG] BAKE FAILED at (%d,%d) mesh=%s" % [coords.x, coords.y, mesh_path])
		else:
			var surfaces = meshes[1].get_surface_count() if meshes.size() > 1 else -1
			var status = "EMPTY" if surfaces == 0 else "ok"
			print("[MapGen CSG] %s at (%d,%d) surfaces=%d mesh=%s" % [status, coords.x, coords.y, surfaces, mesh_path])
