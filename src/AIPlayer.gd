class_name AIPlayer
extends Player

# Custom method called by Game.gd after setup is complete
func start_turn(p_map_node: Node3D):
	"""
	Executes the simple AI logic: build a drone factory near the base.
	"""
	print("AI Player %d (%s) starting turn." % [id, name])
	
	# 1. Check if Base is placed (it should be structures[0] if Game.gd's sequence is followed)
	if structures.size() == 0:
		push_error("AIPlayer %d: Base structure not found." % id)
		return
		
	var base_tile: Tile = structures[0].current_tile
	
	# 2. Find a free, walkable neighbor tile for the Drone Factory
	var factory_tile: Tile = null
	
	for neighbor_tile in base_tile.neighbors:
		# Check if tile is walkable and free of structures
		if is_instance_valid(neighbor_tile) and neighbor_tile.walkable and neighbor_tile.structure == null:
			factory_tile = neighbor_tile
			break
			
	if factory_tile:
		# Attempt to place a drone factory. Player.place_structure handles resource checks.
		var success = place_structure("drone_factory", factory_tile, p_map_node)
		if success:
			print("AI Player %d successfully built drone_factory at %s." % [id, factory_tile.get_coords()])
	else:
		push_error("AI Player %d could not find a free tile next to the base for drone_factory." % id)