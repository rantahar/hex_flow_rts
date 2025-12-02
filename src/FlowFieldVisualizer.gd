extends Node3D
class_name FlowFieldVisualizer

# Dependencies (FlowField is needed for INF constant)
var arrow_mesh: Mesh
var flow_field: FlowField
var grid: Grid
var player_id: int # Used for visualization color/debug

# Configuration
const ARROW_HEIGHT: float = 0.4
const ARROW_OFFSET_Y: float = 0.1 # Offset above the tile center

# Color gradient for Player 0 (0 = Green, Max = Red)
const P0_COLOR_MAX = Color.RED
const P0_COLOR_MID = Color.YELLOW
const P0_COLOR_MIN = Color.GREEN

# Color gradient for Player 1 (0 = Blue, Max = Magenta)
const P1_COLOR_MAX = Color(1.0, 0.0, 1.0) # Magenta/Pink
const P1_COLOR_MID = Color(0.0, 1.0, 1.0) # Cyan
const P1_COLOR_MIN = Color(0.0, 0.0, 1.0) # Blue

var current_arrows: Array[MeshInstance3D] = []

func _ready():
	# Create a basic ConeMesh (the arrow shape) dynamically
	# ConeMesh must be created here or elsewhere with engine context available.
	var cone_mesh = CylinderMesh.new()
	cone_mesh.height = ARROW_HEIGHT
	cone_mesh.top_radius = 0.0
	cone_mesh.bottom_radius = 0.1
	arrow_mesh = cone_mesh
	
func _exit_tree():
	clear_visualization()

# Removes all currently spawned flow field arrows.
func clear_visualization() -> void:
	for arrow in current_arrows:
		arrow.queue_free()
	current_arrows.clear()

# Finds the maximum cost among all tiles to normalize the gradient.
# Tiles should be an Array[Tile] but Godot GDScript 2.0 may handle dynamic typing fine if Tile is class_name.
func _get_max_flow_cost() -> float:
	if not flow_field:
		return 0.0
		
	var max_cost: float = 0.0
	for tile in grid.tiles.values():
		var cost = flow_field.get_flow_cost(tile)
		# Check if cost is a finite positive number
		if cost < FlowField.INF and cost > max_cost:
			max_cost = cost
	return max_cost

# Calculates color based on flow_cost relative to max_cost (0 = Green, Max = Red)
func _get_color_from_cost(cost: float, max_cost: float) -> Color:
	var COLOR_MIN: Color
	var COLOR_MID: Color
	var COLOR_MAX: Color
	
	if player_id == 0:
		COLOR_MIN = P0_COLOR_MIN
		COLOR_MID = P0_COLOR_MID
		COLOR_MAX = P0_COLOR_MAX
	else: # Assume player_id == 1 for demonstration purposes
		COLOR_MIN = P1_COLOR_MIN
		COLOR_MID = P1_COLOR_MID
		COLOR_MAX = P1_COLOR_MAX

	if cost == 0.0:
		return COLOR_MIN # Target is always minimum color
		
	if cost >= FlowField.INF or max_cost == 0.0:
		return COLOR_MAX # Unreachable/Default max cost tiles are maximum color
		
	var ratio: float = cost / max_cost
	
	# 0.0 (Min) -> 0.5 (Mid) -> 1.0 (Max)
	if ratio <= 0.5:
		# Min to Mid
		var local_ratio = ratio * 2.0
		return COLOR_MIN.lerp(COLOR_MID, local_ratio)
	else:
		# Mid to Max
		var local_ratio = (ratio - 0.5) * 2.0
		return COLOR_MID.lerp(COLOR_MAX, local_ratio)

# Spawns arrows on each tile pointing in flow_direction, colored by flow_cost.
# Spawns arrows on each tile pointing in flow_direction, colored by flow_cost.
func visualize() -> void:
	if not flow_field or not grid:
		print("ERROR: FlowField or Grid not set.")
		return
		
	print("DEBUG: Flow field visualization triggered (calculated state for player %d)." % player_id)
	clear_visualization()
	
	var tiles = grid.tiles.values()
	if tiles.is_empty():
		return
		
	var max_cost: float = _get_max_flow_cost()
	
	for tile in tiles:
		var cost = flow_field.get_flow_cost(tile)
		var direction_2d = flow_field.get_flow_direction(tile)

		if cost >= FlowField.INF or cost == 0.0 or direction_2d == Vector2i.ZERO:
			continue

		var arrow = MeshInstance3D.new()
		arrow.mesh = arrow_mesh
		arrow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(arrow)
		current_arrows.append(arrow)

		# 1. Position (Local to FlowFieldVisualizer)
		var world_pos = tile.world_pos
		arrow.position = world_pos + Vector3(0, ARROW_OFFSET_Y, 0)
		
		# 2. Rotation (Flow Direction)
		var direction_3d = Vector3(direction_2d.x, 0, direction_2d.y).normalized()
		
		# 2a. Calculate rotation to align +Z with direction_3d
		var basis_rotation: Basis
		if direction_3d != Vector3.ZERO:
			# Basis.looking_at aligns the Z axis towards the target direction_3d
			basis_rotation = Basis.looking_at(direction_3d, Vector3.UP)
		else:
			basis_rotation = Basis.IDENTITY
			
		# 2b. Rotate Cone from +Y (default mesh axis) to +Z (flow direction axis)
		var rotation_to_align_cone = Transform3D.IDENTITY.rotated(Vector3.RIGHT, deg_to_rad(-90)).basis
		
		# Combine rotations and apply to basis (position is set separately)
		arrow.basis = basis_rotation * rotation_to_align_cone
		
		# 3. Coloring
		var color = _get_color_from_cost(cost, max_cost)
		var material = StandardMaterial3D.new()
		material.albedo_color = color
		arrow.material_override = material

func setup(flow_field: FlowField, grid: Grid, p_player_id: int):
	self.flow_field = flow_field
	self.grid = grid
	self.player_id = p_player_id

func visualize_initial_state(tiles: Array) -> void:
	clear_visualization()
	
	if tiles.is_empty():
		return
		
	# Default rotation setup: point along +Z (using the ConeMesh helper rotation)
	var default_direction = Vector3(0, 0, 1).normalized()
	# Calculate default rotation basis (rotation only, no translation component)
	var rotation_to_align_cone = Transform3D.IDENTITY.rotated(Vector3.RIGHT, deg_to_rad(-90)).basis
	var basis_rotation = Basis.looking_at(default_direction, Vector3.UP)
	var default_basis = basis_rotation * rotation_to_align_cone
	
	# Default color: Cyan/Mid color for P1, since it's an initial visualization
	# We use P1_COLOR_MID to ensure it contrasts with P0 colors (Green/Yellow/Red)
	var material = StandardMaterial3D.new()
	material.albedo_color = P1_COLOR_MID
	
	for tile in tiles:
		var arrow = MeshInstance3D.new()
		arrow.mesh = arrow_mesh
		arrow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(arrow)
		current_arrows.append(arrow)

		# 1. Position (Local to FlowFieldVisualizer)
		var world_pos = tile.world_pos
		arrow.position = world_pos + Vector3(0, ARROW_OFFSET_Y, 0)
		
		# 2. Rotation: Default direction (rotation only)
		arrow.basis = default_basis
		
		# 3. Coloring: Default color
		arrow.material_override = material
