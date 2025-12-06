extends Node3D
class_name StructurePlacer

const GameData = preload("res://data/game_data.gd")
const Tile = preload("res://src/core/Tile.gd")
const Player = preload("res://src/Player.gd")
const Grid = preload("res://src/core/Grid.gd")

# State tracking for placement mode
var active: bool = false
var current_structure_type: String = ""
var placing_player: Player = null

# Placeholder for the visual preview node
var preview_instance = null

func _init():
	# Ensure the node is callable via the Game script
	pass

func is_active() -> bool:
	return active

func enter_placement_mode(structure_type: String):
	current_structure_type = structure_type
	active = true
	
	var config = GameData.STRUCTURE_TYPES.get(structure_type)
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
	if mesh_load is PackedScene:
		# If it's a scene, instantiate it and get the first MeshInstance3D child
		preview_instance = mesh_load.instantiate()
		# Search for MeshInstance3D child (might be nested)
		for child in preview_instance.get_children():
			if child is MeshInstance3D:
				preview_instance = child
				break
	elif mesh_load is Mesh:
		if not is_instance_valid(preview_instance):
			preview_instance = MeshInstance3D.new()
		preview_instance.mesh = mesh_load
	
	if not preview_instance:
		push_error("StructurePlacer: Failed to create preview mesh instance for %s." % structure_type)
		active = false
		return
		
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

	# Dynamically fetch map node from parent (Game)
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
	var mesh_height = mesh.get_aabb().size.y
	var structure_half_height = mesh_height * scale_factor / 2.0
	
	# Adjust Y position: ground_y + (mesh_height * scale_factor / 2.0)
	preview_instance.global_position = Vector3(hovered_tile.world_pos.x, ground_y + structure_half_height, hovered_tile.world_pos.z)
	
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

	# 4. Update preview color based on validation
	var color: Color
	if is_valid:
		color = Color(0.0, 1.0, 0.0, 0.5) # Green, semi-transparent
	else:
		color = Color(1.0, 0.0, 0.0, 0.5) # Red, semi-transparent
		
	if is_instance_valid(preview_instance.material_override) and preview_instance.material_override is StandardMaterial3D:
		preview_instance.material_override.albedo_color = color
	
func _input(event):
	if not active:
		return
	
	# Check for ESC key press (ui_cancel action)
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		exit_placement_mode()
		return
		
	# Check for Right Mouse Button (RMB) press (cancel placement)
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.is_pressed():
		get_viewport().set_input_as_handled()
		exit_placement_mode()
		return

# New method to initialize the human player reference
func set_human_player(player_ref: Player):
	placing_player = player_ref
	print("StructurePlacer: Human Player set to Player %d." % placing_player.id if placing_player else -1)

func attempt_placement(tile: Tile, map_node: Node3D) -> bool:
	# This logic is based on the previously removed Game._on_build_requested logic,
	# which we assume should be handled here now.
	
	if not is_instance_valid(tile) or tile.structure != null:
		print("StructurePlacer: Cannot place here. Tile occupied or invalid.")
		return false
		
	var structure_config = GameData.STRUCTURE_TYPES.get(current_structure_type)
	if not structure_config:
		push_error("StructurePlacer: Invalid structure type %s." % current_structure_type)
		return false
		
	# Player is already stored in placing_player	
	if not is_instance_valid(placing_player):
		push_error("StructurePlacer.attempt_placement: Human player reference is invalid.")
		return false
		
	var cost = structure_config.get("cost", 0.0)
	
	if placing_player.resources < cost:
		print("StructurePlacer: Not enough resources to build %s (Requires %f, Have %f)." % [current_structure_type, cost, placing_player.resources])
		return false

	# Place the structure (Player.gd handles resource deduction and adding to map)
	var success = placing_player.place_structure(current_structure_type, tile, map_node)
	
	# Exit placement mode only if placement was successful? No, usually not. 
	# We let the Game node decide when to exit placement mode (e.g., if we want auto-exit or sustained placement).
	
	return success
