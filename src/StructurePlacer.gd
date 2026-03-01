extends Node3D
class_name StructurePlacer

const GameData = preload("res://data/game_data.gd")


# Constants for placement overlay colors (Now used for global map tinting on entry/exit)
const TINT_COLOR_VALID: Color = Color(0.0, 1.0, 0.0, 0.4) # Green, semi-transparent
const TINT_COLOR_INVALID: Color = Color(1.0, 0.0, 0.0, 0.4) # Red, semi-transparent
const TINT_COLOR_RESET: Color = Color(1.0, 1.0, 1.0, 0.0) # Fully transparent for clearing all tints

# State tracking for placement mode
var active: bool = false
var current_structure_type: String = ""
var placing_player: Player = null
var grid_ref: Grid = null
var reachable_coords: Array[Vector2i] = [] # Stores coordinates whose tiles need tinting for hover logic

# Placeholder for the visual preview node
var preview_instance = null

# Road drawing mode state
var road_mode: bool = false
var road_start_tile: Tile = null
var road_preview_path: Array[Vector2i] = []

func _init():
	# Ensure the node is callable via the Game script
	pass

func is_active() -> bool:
	return active or road_mode

func enter_placement_mode(structure_type: String):
	current_structure_type = structure_type
	active = true

	var config = GameData.STRUCTURE_TYPES.get(structure_type)

	# Step 1: Detect if this is an improvement structure and print the result
	var is_improvement = false
	if config and config.has("category") and config.category == "improvement":
		is_improvement = true
	print("[StructurePlacer] Structure type: %s, is_improvement: %s" % [structure_type, str(is_improvement)])

	# Step 2: Find all base tiles owned by the placing player and print their coordinates
	var base_coords = []
	var allowed_neighbor_coords = []
	if is_improvement:
		if is_instance_valid(grid_ref) and is_instance_valid(placing_player):
			var neighbor_set = {}
			for coords in grid_ref.tiles:
				var tile = grid_ref.tiles[coords]
				if is_instance_valid(tile) and is_instance_valid(tile.structure):
					var base_config = GameData.STRUCTURE_TYPES.get(tile.structure.structure_type)
					if base_config and base_config.has("category") and base_config.category == "base":
						if tile.structure.player_id == placing_player.id:
							base_coords.append(coords)
							# Step 3: Collect all unique neighbor coords
							for neighbor in tile.neighbors:
								if is_instance_valid(neighbor):
									neighbor_set[neighbor.get_coords()] = true
			# Convert keys to array
			allowed_neighbor_coords = neighbor_set.keys()
		print("[StructurePlacer] Base coords for player %s: %s" % [str(placing_player.id) if is_instance_valid(placing_player) else "?", str(base_coords)])
		print("[StructurePlacer] Allowed improvement neighbor coords: %s" % [str(allowed_neighbor_coords)])

		# Step 4: Only allow placement and highlight green on allowed neighbor tiles
		for coords in grid_ref.tiles:
			var tile = grid_ref.tiles[coords]
			var is_allowed = false
			if allowed_neighbor_coords.has(coords):
				is_allowed = tile.is_buildable_terrain() and not is_instance_valid(tile.structure)
			var tint_color = TINT_COLOR_VALID if is_allowed else TINT_COLOR_INVALID
			tile.set_overlay_tint(tint_color)
		return

	# Determine reachable tiles for placement and apply tinting.
	# References should be set via setup() in Game._ready()
	var grid = grid_ref

	if is_instance_valid(grid) and is_instance_valid(placing_player):
		# Find all base structures owned by the player
		var player_base_coords: Array[Vector2i] = []
		for structure in placing_player.structures:
			if is_instance_valid(structure):
				var struct_config = GameData.STRUCTURE_TYPES.get(structure.structure_type)
				if struct_config and struct_config.get("category") == "base":
					player_base_coords.append(structure.current_tile.get_coords())

		# Fallback to spawn_tile if no bases found
		if player_base_coords.is_empty() and is_instance_valid(placing_player.spawn_tile):
			player_base_coords.append(placing_player.spawn_tile.get_coords())

		if player_base_coords.is_empty():
			push_error("StructurePlacer: No bases found for reachability calculation.")
			active = false
			return

		# Calculate reachable tiles from all bases and merge results
		var reachable_set: Dictionary = {}
		for coords in player_base_coords:
			var tiles_from_base = grid.get_reachable_tiles(coords)
			for tile_coord in tiles_from_base:
				reachable_set[tile_coord] = true

		reachable_coords.clear()
		for coord in reachable_set.keys():
			reachable_coords.append(coord)

		print("StructurePlacer: Calculated reachability from %d bases, %d tiles reachable" % [player_base_coords.size(), reachable_coords.size()])

		# Apply tint to all tiles: green only if buildable, unoccupied, AND reachable by builders.
		for coords in grid.tiles:
			var tile: Tile = grid.tiles[coords]
			if is_instance_valid(tile):
				var structure_exists = is_instance_valid(tile.structure)
				var is_reachable = reachable_coords.has(coords)
				var is_valid_for_placement = tile.is_buildable_terrain() and not structure_exists and is_reachable
				var tint_color: Color = TINT_COLOR_VALID if is_valid_for_placement else TINT_COLOR_INVALID
				tile.set_overlay_tint(tint_color)
	else:
		if not is_instance_valid(grid):
			push_error("StructurePlacer: Missing Grid reference. Setup likely failed.")
		elif not is_instance_valid(placing_player):
			push_error("StructurePlacer: Missing Player reference.")

		active = false
		return
	
	
	# 1. Load mesh
	if not config:
		push_error("StructurePlacer: Invalid structure type '%s'." % structure_type)
		active = false
		return
		
	# 1. Load mesh
	var mesh_path = config.get("mesh_path")
	if not mesh_path:
		push_error("StructurePlacer: Missing mesh_path for %s." % structure_type)
		active = false
		return
		
	var mesh_load = load(mesh_path)
	
	# Assert that the loaded resource is a Mesh, as structures are not scenes.
	if not mesh_load is Mesh:
		push_error("StructurePlacer: Loaded asset is not a Mesh for %s." % structure_type)
		active = false
		return
		
	if not is_instance_valid(preview_instance):
		preview_instance = MeshInstance3D.new()
	preview_instance.mesh = mesh_load
	
	# 2. Scale preview instance (same scaling logic as Structure.gd)
	var target_world_radius = Grid.HEX_SCALE * config.size
	var aabb = preview_instance.mesh.get_aabb()
	var current_radius = max(aabb.size.x, aabb.size.z) * 0.5
	var scale_factor = target_world_radius / current_radius
	preview_instance.scale = Vector3(scale_factor, scale_factor, scale_factor)
	
	# 3. Create semi-transparent material (Green default)
	var preview_material = StandardMaterial3D.new()
	preview_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	preview_material.albedo_color = Color(0.0, 1.0, 0.0, 0.5) # Default Green, 50% alpha
	preview_instance.material_override = preview_material
	
	# 4. Add to scene tree and hide initially
	if preview_instance.get_parent() != self:
		add_child(preview_instance)
		
	preview_instance.visible = false
	
	print("StructurePlacer: Entered placement mode for %s (Player %d)" % [structure_type, placing_player.id if placing_player else -1])
	

func exit_placement_mode():
	active = false
	current_structure_type = ""
	
	# --- REQUIREMENT 2: Remove tint from all tiles when exiting placement mode ---
	if is_instance_valid(grid_ref):
		for coords in grid_ref.tiles:
			var tile = grid_ref.tiles.get(coords)
			if is_instance_valid(tile):
				# Use TINT_COLOR_RESET to clear global indicator tints applied on entry.
				tile.set_overlay_tint(TINT_COLOR_RESET)
	
	reachable_coords.clear()
		
	# Clean up preview mesh
	if is_instance_valid(preview_instance):
		preview_instance.visible = false
	
	print("StructurePlacer: Exited placement mode.")

func update_preview(hovered_tile: Tile):
	# 1. Hide preview and return if no tile is hovered
	if not is_instance_valid(hovered_tile):
		if is_instance_valid(preview_instance):
			preview_instance.visible = false
		return
		
	if not is_instance_valid(preview_instance):
		return

	# Dynamically fetch map node from parent (Game) for map_node.get_height_at_world_pos
	# NOTE: grid_ref is set via setup()
	var game_node = get_parent()
	if not is_instance_valid(game_node) or not is_instance_valid(game_node.map_node):
		push_error("StructurePlacer: Cannot find Map node reference on parent Game node.")
		return
	var map_node = game_node.map_node
	
	preview_instance.visible = true
	
	var structure_config = GameData.STRUCTURE_TYPES.get(current_structure_type)
	if not structure_config:
		push_error("StructurePlacer: Cannot find configuration for %s." % current_structure_type)
		return

	# 2. Positioning (World position + height correction)
	
	# Get ground height using raycast (copy _get_ground_height() logic from Structure.gd via Map.gd)
	var ground_y: float = map_node.get_height_at_world_pos(hovered_tile.world_pos)
	
	# Calculate scaled mesh height
	var mesh = preview_instance.mesh
	
	# Safety check for mesh existence
	if not is_instance_valid(mesh):
		return
	
	var scale_factor = preview_instance.scale.y # Scale is uniform
	var structure_height = mesh.get_aabb().size.y * scale_factor
	
	# Get vertical offset configuration (0.0 for standard placement, negative to sink)
	var y_offset_fraction = structure_config.get("y_offset_fraction", 0.0)
	
	# Adjust Y position using generalized placement: ground_y + (structure_height * offset_fraction)
	# This aligns with the placement logic in Structure.gd
	preview_instance.global_position = Vector3(hovered_tile.world_pos.x, ground_y + (structure_height * y_offset_fraction), hovered_tile.world_pos.z)
	
	# 3. Validate placement
	var is_valid: bool = true
	
	# Check tile buildable terrain
	if not hovered_tile.is_buildable_terrain():
		is_valid = false
	
	# Check tile.structure == null
	if is_instance_valid(hovered_tile.structure):
		is_valid = false
	
	# Retrieve Player instance
	var player = placing_player
	
	if not is_instance_valid(player):
		is_valid = false

	# Check player.can_afford(current_structure_type)
	if is_valid and not player.can_afford(current_structure_type):
		is_valid = false


# New method to initialize core references
func setup(grid: Grid):
	grid_ref = grid
	print("StructurePlacer: Grid reference set.")

# New method to initialize the human player reference
func set_human_player(player_ref: Player):
	placing_player = player_ref
	print("StructurePlacer: Human Player set to Player %d." % placing_player.id if placing_player else -1)

func attempt_placement(tile: Tile, map_node: Node3D) -> bool:
	# Restrict placement for improvements to allowed neighbor tiles
	var structure_config = GameData.STRUCTURE_TYPES.get(current_structure_type)
	if not structure_config:
		push_error("StructurePlacer: Invalid structure type %s." % current_structure_type)
		return false

	var is_improvement = structure_config.has("category") and structure_config.category == "improvement"
	if is_improvement:
		# Recompute allowed neighbor coords (mirrors enter_placement_mode logic)
		var allowed_neighbor_coords = []
		if is_instance_valid(grid_ref) and is_instance_valid(placing_player):
			var neighbor_set = {}
			for coords in grid_ref.tiles:
				var t = grid_ref.tiles[coords]
				if is_instance_valid(t) and is_instance_valid(t.structure):
					var base_config = GameData.STRUCTURE_TYPES.get(t.structure.structure_type)
					if base_config and base_config.has("category") and base_config.category == "base":
						if t.structure.player_id == placing_player.id:
							for neighbor in t.neighbors:
								if is_instance_valid(neighbor):
									neighbor_set[neighbor.get_coords()] = true
			allowed_neighbor_coords = neighbor_set.keys()
		if not allowed_neighbor_coords.has(tile.get_coords()):
			print("StructurePlacer: Cannot place improvement here. Not adjacent to base.")
			return false

	# For non-improvements, verify the tile is reachable by builders from a base.
	if not is_improvement:
		if not reachable_coords.has(tile.get_coords()):
			print("StructurePlacer: Cannot place here. Tile is not reachable from any base.")
			return false

	# Standard checks for all structures
	if not is_instance_valid(tile) or tile.structure != null:
		print("StructurePlacer: Cannot place here. Tile occupied or invalid.")
		return false
	if not is_instance_valid(placing_player):
		push_error("StructurePlacer.attempt_placement: Human player reference is invalid.")
		return false
	var cost = structure_config.get("cost", 0.0)
	if placing_player.resources < cost:
		print("StructurePlacer: Not enough resources to build %s (Requires %f, Have %f)." % [current_structure_type, cost, placing_player.resources])
		return false

	# Place the structure (Player.gd handles resource deduction and adding to map)
	var success = placing_player.place_structure(current_structure_type, tile, map_node)
	if success and is_instance_valid(tile):
		tile.set_overlay_tint(TINT_COLOR_RESET)
	return success

# --- Road Drawing Mode ---

const TINT_COLOR_ROAD_PREVIEW: Color = Color(0.6, 0.4, 0.2, 0.5)
const TINT_COLOR_ROAD_START: Color = Color(1.0, 1.0, 0.0, 0.5)

func enter_road_mode():
	road_mode = true
	road_start_tile = null
	road_preview_path.clear()

	if is_instance_valid(grid_ref):
		for coords in grid_ref.tiles:
			var tile = grid_ref.tiles[coords]
			if is_instance_valid(tile):
				# All tiles are valid for roads (including water, at higher cost)
				var tint = TINT_COLOR_VALID if not tile.has_road else TINT_COLOR_RESET
				tile.set_overlay_tint(tint)

	print("StructurePlacer: Entered road drawing mode.")

func exit_road_mode():
	road_mode = false
	road_start_tile = null
	_clear_road_preview()

	# Clear all overlay tints (road visuals are handled by line meshes in Tile)
	if is_instance_valid(grid_ref):
		for coords in grid_ref.tiles:
			var tile = grid_ref.tiles.get(coords)
			if is_instance_valid(tile):
				tile.set_overlay_tint(TINT_COLOR_RESET)

	print("StructurePlacer: Exited road drawing mode.")

func update_road_preview(hovered_tile: Tile):
	if not road_mode or not is_instance_valid(hovered_tile) or not is_instance_valid(grid_ref):
		return

	if not is_instance_valid(road_start_tile):
		return

	# Clear previous preview
	_clear_road_preview()

	# Calculate path from start to hovered tile
	road_preview_path = grid_ref.find_path(road_start_tile.get_coords(), hovered_tile.get_coords())

	# Tint preview path tiles
	for coords in road_preview_path:
		var tile = grid_ref.tiles.get(coords)
		if is_instance_valid(tile):
			tile.set_overlay_tint(TINT_COLOR_ROAD_PREVIEW)

	# Keep start tile highlighted
	road_start_tile.set_overlay_tint(TINT_COLOR_ROAD_START)

func attempt_road_click(tile: Tile) -> bool:
	if not road_mode or not is_instance_valid(tile) or not is_instance_valid(grid_ref):
		return false

	# First click: set start tile
	if not is_instance_valid(road_start_tile):
		road_start_tile = tile
		tile.set_overlay_tint(TINT_COLOR_ROAD_START)
		print("StructurePlacer: Road start set at %s" % tile.get_coords())
		return true

	# Second click: build road along path
	var path = grid_ref.find_path(road_start_tile.get_coords(), tile.get_coords())
	if path.is_empty():
		print("StructurePlacer: No path found for road.")
		return false

	# Calculate total cost
	var total_cost: float = 0.0
	var road_config = GameData.ROAD_CONFIG
	for coords in path:
		var path_tile = grid_ref.tiles.get(coords)
		if is_instance_valid(path_tile) and not path_tile.has_road and not path_tile.road_under_construction:
			if path_tile.walkable:
				total_cost += road_config.cost_per_segment
			else:
				total_cost += road_config.cost_per_segment * road_config.water_cost_multiplier

	# Check affordability
	if not is_instance_valid(placing_player) or placing_player.resources < total_cost:
		print("StructurePlacer: Not enough resources for road. Need %0.0f, have %0.0f." % [total_cost, placing_player.resources if is_instance_valid(placing_player) else 0.0])
		return false

	# Deduct resources and mark tiles as under construction
	placing_player.add_resources(-total_cost)

	var road_tiles: Array = []
	for coords in path:
		var path_tile = grid_ref.tiles.get(coords)
		if is_instance_valid(path_tile) and not path_tile.has_road and not path_tile.road_under_construction:
			var segment_cost: float = road_config.cost_per_segment
			if not path_tile.walkable:
				segment_cost *= road_config.water_cost_multiplier
			path_tile.set_road_under_construction(segment_cost)
			road_tiles.append(path_tile)

	# Register road tiles with nearest base construction queues
	placing_player.register_road_construction(road_tiles)

	print("StructurePlacer: Road construction started with %d segments for %0.0f resources." % [road_tiles.size(), total_cost])

	# Reset for next road segment
	_clear_road_preview()
	road_start_tile = null
	road_preview_path.clear()
	return true

func _clear_road_preview():
	for coords in road_preview_path:
		if is_instance_valid(grid_ref) and grid_ref.tiles.has(coords):
			var tile = grid_ref.tiles[coords]
			if is_instance_valid(tile):
				# Restore to green (buildable) tint during road mode
				tile.set_overlay_tint(TINT_COLOR_VALID if (not tile.has_road and not tile.road_under_construction) else TINT_COLOR_RESET)
	road_preview_path.clear()

func get_road_preview_cost() -> float:
	if road_preview_path.is_empty() or not is_instance_valid(grid_ref):
		return 0.0
	var total: float = 0.0
	var road_config = GameData.ROAD_CONFIG
	for coords in road_preview_path:
		var tile = grid_ref.tiles.get(coords)
		if is_instance_valid(tile) and not tile.has_road and not tile.road_under_construction:
			if tile.walkable:
				total += road_config.cost_per_segment
			else:
				total += road_config.cost_per_segment * road_config.water_cost_multiplier
	return total
