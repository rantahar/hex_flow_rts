extends Node3D
class_name FlowFieldVisualizer

# Dependencies (FlowField is needed for INF constant)
var arrow_mesh: Mesh

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
# Assumes tiles are available via p_grid.
func _get_max_flow_cost(p_flow_field: FlowField, p_grid: Grid) -> float:
	if not p_flow_field:
		return 0.0
		
	var max_cost: float = 0.0
	for tile in p_grid.tiles.values():
		var cost = p_flow_field.get_flow_cost(tile)
		# Check if cost is a finite positive number
		if cost < FlowField.INF and cost > max_cost:
			max_cost = cost
	return max_cost

# Calculates color based on flow_cost relative to max_cost (0 = Green, Max = Red)
func _get_color_from_cost(cost: float, max_cost: float, p_player_id: int) -> Color:
	var COLOR_MIN: Color
	var COLOR_MID: Color
	var COLOR_MAX: Color
	
	if p_player_id == 0:
		COLOR_MIN = P0_COLOR_MIN
		COLOR_MID = P0_COLOR_MID
		COLOR_MAX = P0_COLOR_MAX
	else: # Use Player 1 colors for all other player IDs (e.g., p_player_id == 1)
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

func update_visualization(p_flow_field: FlowField, p_grid: Grid, p_player_id: int) -> void:
	clear_visualization()
	
	if not p_flow_field or not p_grid:
		print("ERROR: FlowField or Grid not provided.")
		return
	
	var tiles = p_grid.tiles.values()
	if tiles.is_empty():
		return
	
	var max_cost: float = _get_max_flow_cost(p_flow_field, p_grid)
	
	for tile in tiles:
		var cost = p_flow_field.get_flow_cost(tile)
		var next_tile = p_flow_field.get_next_tile(tile, p_grid)
		
		if cost >= FlowField.INF or cost == 0.0 or not next_tile:
			continue
		
		var arrow = MeshInstance3D.new()
		arrow.mesh = arrow_mesh
		arrow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(arrow)
		current_arrows.append(arrow)
		
		var world_pos = tile.world_pos
		arrow.position = world_pos + Vector3(0, ARROW_OFFSET_Y, 0)
		
		var direction_3d = (next_tile.world_pos - world_pos).normalized()
		direction_3d.y = 0.0 # Ensure it's purely planar direction
		
		var basis_rotation: Basis
		if direction_3d != Vector3.ZERO:
			# Use Z-axis pointing forward convention (hexagonal grid)
			basis_rotation = Basis.looking_at(direction_3d, Vector3.UP)
		else:
			basis_rotation = Basis.IDENTITY
		
		# Rotate the cone mesh 90 degrees around X to align its tip (currently pointing up/Y) with its local Z-axis (forward)
		var rotation_to_align_cone = Transform3D.IDENTITY.rotated(Vector3.RIGHT, deg_to_rad(-90)).basis
		arrow.basis = basis_rotation * rotation_to_align_cone
		
		var color = _get_color_from_cost(cost, max_cost, p_player_id)
		var material = StandardMaterial3D.new()
		material.albedo_color = color
		arrow.material_override = material
