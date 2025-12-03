class_name FlowField
var player_id: int
var flow_data: Dictionary = {}  # Format: {Vector2i(x,z): {cost: float, direction: Vector2i}}

# Godot's built-in infinity constant for floats
const INF: float = 1e20
const DENSITY_COST_MULTIPLIER = 1

# Calculates the flow field using Dijkstra's algorithm
# starting from the targets with specified initial costs.
# targets: {Tile: float} - Dictionary mapping target Tiles to their initial flow cost (priority).
# Stores flow field data internally in flow_data structure.
func calculate(targets: Dictionary, grid: Grid) -> void:
	if not grid:
		push_error("FlowField.calculate: Grid is null")
		return
	
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
			if not visited.has(neighbor_tile) and neighbor_tile.walkable:
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
			if not neighbor_tile.walkable:
				continue
				
			var neighbor_coords = neighbor_tile.get_coords()
			
			if not flow_data.has(neighbor_coords):
				continue

			var neighbor_flow_cost: float = flow_data[neighbor_coords]["cost"]
				
			var new_cost: float = current_cost + neighbor_tile.cost
			
			# Relaxation
			if new_cost < neighbor_flow_cost:
				flow_data[neighbor_coords]["cost"] = new_cost
				queue.append(neighbor_tile)

	# 2.5. Apply friendly unit density cost penalty
	for tile_to_check in all_tiles:
		var coords = tile_to_check.get_coords()
		if flow_data.has(coords):
			var friendly_unit_count: int = 0
			# NOTE: Assumes tile_to_check.occupied_slots is an array of units/objects with 'player_id'
			if tile_to_check.occupied_slots:
				for unit in tile_to_check.occupied_slots:
					if unit != null and is_instance_valid(unit) and unit.player_id == player_id:
						friendly_unit_count += 1
			
			if friendly_unit_count > 0:
				var density_cost = friendly_unit_count * DENSITY_COST_MULTIPLIER
				flow_data[coords]["cost"] += density_cost

	# 3. Flow Direction Assignment
	for tile_to_check in all_tiles:
		var tile_coords = tile_to_check.get_coords()
		
		if not flow_data.has(tile_coords):
			continue
			
		var tile_flow_data = flow_data[tile_coords]
		
		# Check if the tile is reachable (not INF)
		if tile_flow_data["cost"] != INF:
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
			# Only update direction if a lower cost neighbor was found.
			if best_neighbor_coords != Vector2i.ZERO and min_cost < tile_flow_data["cost"]:
				var flow_direction = best_neighbor_coords - tile_coords
				# flow_direction is the Vector2i offset from the current tile to the lowest cost neighbor
				flow_data[tile_coords]["direction"] = flow_direction

## Query Methods ##

func get_flow_cost(tile: Tile) -> float:
	if not tile:
		push_error("FlowField.get_flow_cost: Tile is null")
		return INF
	var coords = tile.get_coords()
	if flow_data.has(coords):
		return flow_data[coords]["cost"]
	return INF

func get_next_tile(current_tile: Tile, grid: Grid) -> Tile:
	var flow_direction = get_flow_direction(current_tile)
	if flow_direction == Vector2i.ZERO:
		return null
	
	var next_coords = current_tile.get_coords() + flow_direction
	return grid.tiles.get(next_coords) as Tile
func get_flow_direction(tile: Tile) -> Vector2i:
	if not tile:
		push_error("FlowField.get_flow_direction: Tile is null")
		return Vector2i.ZERO
	var coords = tile.get_coords()
	if flow_data.has(coords):
		return flow_data[coords]["direction"]
	return Vector2i.ZERO

func get_flow_data(coords: Vector2i): # -> Dictionary or null
	if flow_data.has(coords):
		return flow_data[coords]
	return null
