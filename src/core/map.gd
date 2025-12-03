extends Node3D

@onready var map_generator = $MapGenerator
@onready var grid: Grid = $Grid

func _ready():
	# 1. Generate the map (which also instantiates tile nodes)
	map_generator.generate_map()
	
	# 2. Register the generated tiles with the Grid
	grid.register_tiles(map_generator.get_tiles())

# Finds the actual height (Y-coordinate) of the terrain at the given planar world position (x, z).
# This performs a raycast to hit the terrain mesh, accounting for uneven terrain.
func get_height_at_world_pos(world_pos: Vector3) -> float:
	if not is_inside_tree():
		push_error("Map node is not in tree, cannot perform raycast.")
		return 0.0
		
	# Get the Physics direct space state
	var space = get_world_3d().space
	var state = PhysicsServer3D.space_get_direct_state(space)
	
	# Define a vertical ray from high above to far below the map at the given XZ coordinates
	var ray_start = Vector3(world_pos.x, 100.0, world_pos.z)
	var ray_end = Vector3(world_pos.x, -100.0, world_pos.z)
	
	var query = PhysicsRayQueryParameters3D.create(ray_start, ray_end)
	
	var intersection = state.intersect_ray(query)
	
	if intersection.is_empty():
		push_warning("Map.get_height_at_world_pos: Raycast missed terrain at %s. Falling back to 0.0 height." % world_pos)
		return 0.0
	
	# Return the height of the intersection point
	return intersection.position.y
