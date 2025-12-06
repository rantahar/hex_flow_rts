class_name FlowField
var player_id: int
var flow_data: Dictionary = {}  # Format: {Vector2i(x,z): {cost: float, direction: Vector2i}}

# Godot's built-in infinity constant for floats
const INF: float = 1e20
const GameConfig = preload("res://data/game_config.gd")

# Calculates the flow field using Dijkstra's algorithm
# starting from the targets with specified initial costs.
# targets: {Tile: float} - Dictionary mapping target Tiles to their initial flow cost (priority).
# Stores flow field data internally in flow_data structure.
func calculate(targets: Dictionary, grid: Grid) -> void:
	"""
	Calculates the flow field (integration field) using a modified Dijkstra's algorithm.
	This flow field determines the lowest-cost path from any tile back to the target tiles.
	Enemy-occupied tiles are automatically added as targets (cost 0.0) to encourage unit movement towards conflict.

	Arguments:
	- targets (Dictionary): Map of {Tile: float} where the float is the initial cost (priority) of the target.
	- grid (Grid): The map grid containing all Tile objects.
	"""
	if not grid:
		push_error("FlowField.calculate: Grid is null")
		return
	
	# Add enemy tiles (containing enemy units or structures) to targets if not already present
	# This ensures units engage nearby enemy units/structures.
	for tile in grid.tiles.values():
		if tile.is_flow_target(player_id):
			if not targets.has(tile):
				# Assign a base cost of 0.0 to make enemy tiles flow targets
				targets[tile] = 0.0

	if targets.is_empty():
		push_warning("FlowField.calculate: No targets provided for player %d" % player_id)
		return
	
	flow_data.clear()
	
	var initial_targets = targets.keys() # Assumes targets maps Tile -> float
	if initial_targets.is_empty():
		return
		
	# 1. Traversal (to collect all reachable tiles and initialize flow_data)
	var all_tiles: Array[Tile] = []
	var queue = initial_targets.duplicate()
	var visited: Dictionary = {}
	
	# Initialize visited and flow_data entry for all targets
	for tile in initial_targets:
		visited[tile] = true
		all_tiles.append(tile)
		# Initialize flow data for reachable tiles
		flow_data[tile.get_coords()] = {"cost": INF, "direction": Vector2i.ZERO}
		
	var head: int = 0
	while head < queue.size():
		var current_tile: Tile = queue[head]
		head += 1
		
		for neighbor_tile in current_tile.neighbors:
			# Include all tiles bordering a reachable tile in the graph, even if they are blocked (INF cost).
			# This allows flow direction to be calculated away from blocked tiles (like friendly structures).
			if not visited.has(neighbor_tile):
				visited[neighbor_tile] = true
				all_tiles.append(neighbor_tile)
				flow_data[neighbor_tile.get_coords()] = {"cost": INF, "direction": Vector2i.ZERO}
				queue.append(neighbor_tile)
	
	# 2. Dijkstra/BFS Cost Calculation (Multi-source)
	# Re-initialize queue with initial_targets for the actual cost propagation.
	queue = initial_targets.duplicate()
	
	# Set initial flow costs based on priority
	for target_tile in initial_targets:
		var coords = target_tile.get_coords()
		flow_data[coords]["cost"] = targets[target_tile]
	
	# Start propagation
	head = 0
	while head < queue.size():
		var current_tile: Tile = queue[head]
		head += 1
		
		var current_coords = current_tile.get_coords()
		var current_cost: float = flow_data[current_coords]["cost"]
		
		for neighbor_tile in current_tile.neighbors:
			# Get the cost of moving onto the neighbor tile, including terrain, structure blocking, and unit density
			var neighbor_cost_total = neighbor_tile.get_flow_cost(player_id)
			
			if neighbor_cost_total == INF:
				continue
				
			var neighbor_coords = neighbor_tile.get_coords()
			
			if not flow_data.has(neighbor_coords):
				continue

			var neighbor_flow_cost: float = flow_data[neighbor_coords]["cost"]
				
			# Calculate the new accumulated cost
			# neighbor_cost_total already includes terrain cost and friendly unit density cost.
			# It is 0.0 if the tile is a target (enemy unit/structure).
			var new_cost: float = current_cost + neighbor_cost_total
			
			# Relaxation
			if new_cost < neighbor_flow_cost:
				flow_data[neighbor_coords]["cost"] = new_cost
				queue.append(neighbor_tile)

	# 3. Flow Direction Assignment
	for tile_to_check in all_tiles:
		var tile_coords = tile_to_check.get_coords()
		
		if not flow_data.has(tile_coords):
			continue
			
		var tile_flow_data = flow_data[tile_coords]
		
		# We calculate flow direction even for blocked tiles (INF cost),
		# allowing units to move away from them towards the lowest cost neighbor.
		
		# Find the neighbor with the minimum flow cost
		var best_neighbor_coords: Vector2i = Vector2i.ZERO
		var min_cost: float = INF
		
		for neighbor_tile in tile_to_check.neighbors:
			var neighbor_coords = neighbor_tile.get_coords()
			
			if flow_data.has(neighbor_coords):
				var neighbor_cost = flow_data[neighbor_coords]["cost"]
				
				# Find the neighbor with the minimum flow_cost
				if neighbor_cost < min_cost:
					min_cost = neighbor_cost
					best_neighbor_coords = neighbor_coords
		
		# Check if we found a path to a better tile (i.e. cost is lower than current tile's cost)
		# Note: If the current tile cost is INF, min_cost is almost always less than current cost.
		if best_neighbor_coords != Vector2i.ZERO and min_cost < tile_flow_data["cost"]:
			var flow_direction = best_neighbor_coords - tile_coords
			# flow_direction is the Vector2i offset from the current tile to the lowest cost neighbor
			flow_data[tile_coords]["direction"] = flow_direction

## Query Methods ##

func get_flow_cost(tile: Tile) -> float:
	"""
	Retrieves the calculated cost (distance) for a tile to reach the nearest flow target.

	Arguments:
	- tile (Tile): The tile to query.

	Returns:
	- float: The flow cost, or INF if the tile is unreachable or invalid.
	"""
	if not tile:
		push_error("FlowField.get_flow_cost: Tile is null")
		return INF
	var coords = tile.get_coords()
	if flow_data.has(coords):
		return flow_data[coords]["cost"]
	return INF

func get_next_tile(current_tile: Tile, grid: Grid) -> Tile:
	"""
	Determines the next optimal tile to move to from the current tile based on the flow direction.

	Arguments:
	- current_tile (Tile): The tile the unit is currently on.
	- grid (Grid): The map grid for coordinate lookup.

	Returns:
	- Tile: The next Tile instance to move towards, or null if at the target or flow direction is undefined.
	"""
	var flow_direction = get_flow_direction(current_tile)
	if flow_direction == Vector2i.ZERO:
		return null
	
	var next_coords = current_tile.get_coords() + flow_direction
	return grid.tiles.get(next_coords) as Tile
func get_flow_direction(tile: Tile) -> Vector2i:
	"""
	Retrieves the calculated flow direction (offset vector) for a given tile.
	This vector points from the current tile to the neighbor with the lowest cost.

	Arguments:
	- tile (Tile): The tile to query.

	Returns:
	- Vector2i: The flow direction offset, or Vector2i.ZERO if undefined (e.g., at target).
	"""
	if not tile:
		push_error("FlowField.get_flow_direction: Tile is null")
		return Vector2i.ZERO
	var coords = tile.get_coords()
	if flow_data.has(coords):
		return flow_data[coords]["direction"]
	return Vector2i.ZERO

func get_flow_data(coords: Vector2i): # -> Dictionary or null
	"""
	Retrieves the raw flow data (cost and direction) for a tile coordinate.

	Arguments:
	- coords (Vector2i): The grid coordinates (x, z).

	Returns:
	- Dictionary or null: The flow data dictionary, or null if coordinates are not in the field.
	"""
	if flow_data.has(coords):
		return flow_data[coords]
	return null
