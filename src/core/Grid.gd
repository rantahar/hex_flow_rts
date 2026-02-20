extends Node
class_name Grid

const GameData = preload("res://data/game_data.gd")

# Hex grid geometry constants
# HEX_SCALE is kept as a literal here because Tile.gd references it in a const chain
# (FORMATION_RADIUS). The canonical definition to change is GameConfig.HEX_SCALE.
const HEX_SCALE: float = 0.6  # must match GameConfig.HEX_SCALE
const X_SPACING: float = 1.732 * 0.57735  # sqrt(3) * 0.57735
const Z_SPACING: float = 1.5 * 0.57735

var MAP_X_MIN: float = 0.0
var MAP_X_MAX: float = 0.0
var MAP_Z_MIN: float = 0.0
var MAP_Z_MAX: float = 0.0

func _init():
	"""
	Constructor. Calculates and sets the world bounds (min/max X/Z coordinates) for the map
	based on the configured map width and height.
	"""
	# Load game data to get map dimensions
	# Assumes data/game_data.gd is available
	var game_data = load("res://data/game_data.gd")
	var W = game_data.MAP_WIDTH
	var H = game_data.MAP_HEIGHT
	
	# Calculate the map boundaries.
	MAP_X_MIN = 0.0
	MAP_X_MAX = float(W) * X_SPACING * HEX_SCALE
	MAP_Z_MIN = 0.0
	MAP_Z_MAX = float(H) * Z_SPACING * HEX_SCALE


# Hex grid neighbor offsets (Odd-R offset coordinates)
# Used to determine coordinates of neighboring tiles.
# Order: NW, NE, E, SE, SW, W
const ODD_R_NEIGHBOR_OFFSETS_EVEN: Array[Vector2i] = [
	Vector2i(-1, -1), Vector2i(0, -1), # NW, NE
	Vector2i(1, 0), # E
	Vector2i(0, 1), Vector2i(-1, 1), # SE, SW
	Vector2i(-1, 0) # W
]

const ODD_R_NEIGHBOR_OFFSETS_ODD: Array[Vector2i] = [
	Vector2i(0, -1), Vector2i(1, -1), # NW, NE
	Vector2i(1, 0), # E
	Vector2i(1, 1), Vector2i(0, 1), # SE, SW
	Vector2i(-1, 0) # W
]

# Stores Tile objects keyed by grid coordinates (x, z)
# Format: {Vector2i(x, z): Tile}
var tiles: Dictionary = {}

# Stores reverse lookup keyed by tile node reference
# Format: {Node3D: Vector2i(x, z)}
var node_to_coords: Dictionary = {}

## Registers a newly created tile with its grid coordinates, world position, and node reference.
func register_tiles(new_tiles: Dictionary):
	"""
	Registers all generated Tile objects with the grid, populates the coordinate-to-tile map,
	and initiates the neighbor connection process.

	Arguments:
	- new_tiles (Dictionary): A dictionary of Tile objects keyed by their Vector2i coordinates.
	"""
	# Clear existing tiles and reverse lookup
	tiles.clear()
	node_to_coords.clear()
	
	tiles = new_tiles
	
	# Populate reverse lookup
	connect_neighbors()
	for coords in tiles:
		var tile: Tile = tiles[coords]
		node_to_coords[tile] = coords

## Performs a reverse lookup to find the grid coordinates associated with a specific tile node.
func find_tile_by_node(node: Node3D) -> Vector2i:
	"""
	Performs a reverse lookup to find the grid coordinates associated with a specific tile Node3D instance.

	Arguments:
	- node (Node3D): The Node3D instance of the tile.

	Returns:
	- Vector2i: The grid coordinates (x, z) of the tile, or Vector2i(-1, -1) if not found.
	"""
	if node_to_coords.has(node):
		return node_to_coords[node]
	# Return an invalid coordinate to indicate tile not found, assuming x, z >= 0.
	return Vector2i(-1, -1)

func get_map_bounds() -> Dictionary:
	"""
	Returns the pre-calculated world boundaries of the map (used primarily for camera constraints).

	Returns:
	- Dictionary: Contains "x_min", "x_max", "z_min", and "z_max" world coordinates.
	"""
	return {
		"x_min": MAP_X_MIN,
		"x_max": MAP_X_MAX,
		"z_min": MAP_Z_MIN,
		"z_max": MAP_Z_MAX
	}

func hex_to_world(x: int, z: int) -> Vector3:
	"""
	Retrieves the world position (center) of the tile at the given hex coordinates.

	Arguments:
	- x (int): The X grid coordinate.
	- z (int): The Z grid coordinate (Y in Godot's Vector2i).

	Returns:
	- Vector3: The world position of the tile center, or Vector3.ZERO on error.
	"""
	var coords = Vector2i(x, z)
	if not tiles.has(coords):
		push_error("Grid.hex_to_world: No tile at coordinates (%d, %d)" % [x, z])
		return Vector3.ZERO
	return tiles[coords].world_pos

func world_to_hex(world_pos: Vector3) -> Vector2i:
	"""
	Converts a world position (Vector3) to Odd-R hex grid coordinates (Vector2i).
	
	Arguments:
	- world_pos (Vector3): The world position.
	
	Returns:
	- Vector2i: The corresponding hex coordinates (x, z).
	"""
	var z_hex_float = round(world_pos.z / Z_SPACING)
	var z_hex = int(z_hex_float)
	
	# Calculate raw x based on row parity correction
	var x_raw = world_pos.x / X_SPACING
	var x_offset = 0.0
	if z_hex % 2 != 0:
		x_offset = 0.5
	
	var x_hex = round(x_raw - x_offset)
	
	return Vector2i(x_hex, z_hex)

func is_valid_coords(coords: Vector2i) -> bool:
	"""
	Checks if a given coordinate pair exists within the map grid.

	Arguments:
	- coords (Vector2i): The grid coordinates (x, z).

	Returns:
	- bool: True if the coordinates are valid, false otherwise.
	"""
	return tiles.has(coords)

func get_tile_by_coords(coords: Vector2i):
	"""
	Retrieves the Tile object instance at the specified grid coordinates.

	Arguments:
	- coords (Vector2i): The grid coordinates (x, z).

	Returns:
	- Tile: The Tile instance, or null if no tile exists at those coordinates.
	"""
	if tiles.has(coords):
		return tiles[coords]
	return null

func connect_neighbors():
	"""
	Iterates over all tiles and determines their valid neighbors based on the Odd-R offset system.
	Populates the `neighbors` array in each Tile object.
	Also ensures the tile's x and z coordinates are stored directly on the Tile object.
	"""
	# Iterate over every tile in the grid
	for coords in tiles:
		var tile: Tile = tiles[coords]
		
		var offsets: Array[Vector2i]
		# Determine offsets based on row parity (Odd-R offset)
		if coords.y % 2 == 0:
			offsets = ODD_R_NEIGHBOR_OFFSETS_EVEN
		else:
			offsets = ODD_R_NEIGHBOR_OFFSETS_ODD
			
		# Find and assign neighbor Tile references
		for offset in offsets:
			var neighbor_coords = coords + offset
			if tiles.has(neighbor_coords):
				tile.neighbors.append(tiles[neighbor_coords] as Tile)
				
		# Store coordinates in the Tile object for quick access and consistency.
		tile.x = coords.x
		tile.z = coords.y

func get_reachable_tiles(start_coord: Vector2i) -> Array[Vector2i]:
	"""
	Performs a Breadth-First Search (BFS) to find all tiles reachable from the starting
	coordinate via walkable terrain or completed roads (which bridge over water).

	Arguments:
	- start_coord (Vector2i): The grid coordinate (x, z) to start the search from.

	Returns:
	- Array[Vector2i]: An array of coordinates for all reachable tiles.
	"""
	var start_tile: Tile = get_tile_by_coords(start_coord)

	const INF: float = 1e20

	if start_tile == null or not start_tile.walkable or start_tile.cost >= INF:
		return []

	var queue: Array = [start_tile]
	var visited: Dictionary = {start_coord: true}
	var reachable_coords: Array[Vector2i] = [start_coord]

	while not queue.is_empty():
		var current_tile: Tile = queue.pop_front()

		for neighbor_tile in current_tile.neighbors:
			var neighbor_coord: Vector2i = neighbor_tile.get_coords()
			if visited.has(neighbor_coord):
				continue
			# Traversable if walkable terrain OR a completed road (bridges over water)
			var is_traversable: bool = (neighbor_tile.walkable and neighbor_tile.cost < INF) \
				or (neighbor_tile.has_road and not neighbor_tile.road_under_construction)
			if is_traversable:
				visited[neighbor_coord] = true
				reachable_coords.append(neighbor_coord)
				queue.append(neighbor_tile)

	return reachable_coords

func find_path(from_coords: Vector2i, to_coords: Vector2i, walkable_only: bool = false) -> Array[Vector2i]:
	"""
	Point-to-point pathfinding.

	walkable_only = false (default): plain BFS over all tiles — used for road-drawing
	preview where roads can be drawn over water and hop count is the relevant metric.

	walkable_only = true: Dijkstra over passable tiles (walkable terrain + completed roads)
	weighted by travel cost matching Builder._physics_process (road = 0.3, grass/dirt = 1.0,
	mountain = 2.0). Builders will prefer road routes even when they require more hops.
	"""
	if not tiles.has(from_coords) or not tiles.has(to_coords):
		return []
	if from_coords == to_coords:
		return [from_coords]
	if walkable_only:
		return _find_path_dijkstra(from_coords, to_coords)
	return _find_path_bfs(from_coords, to_coords)

# BFS over all tiles — road drawing preview (hop count only, no walkability filter).
func _find_path_bfs(from_coords: Vector2i, to_coords: Vector2i) -> Array[Vector2i]:
	var queue: Array = [from_coords]
	var came_from: Dictionary = {from_coords: Vector2i(-1, -1)}

	while not queue.is_empty():
		var current: Vector2i = queue.pop_front()
		if current == to_coords:
			break
		for neighbor_tile in tiles[current].neighbors:
			var nc: Vector2i = neighbor_tile.get_coords()
			if not came_from.has(nc):
				came_from[nc] = current
				queue.append(nc)

	return _reconstruct_path(came_from, to_coords)

# Dijkstra over walkable terrain + completed roads, weighted by tile travel cost.
func _find_path_dijkstra(from_coords: Vector2i, to_coords: Vector2i) -> Array[Vector2i]:
	const BIG: float = 1e20
	var road_cost: float = GameData.ROAD_CONFIG.road_tile_cost

	var dist: Dictionary = {from_coords: 0.0}
	var came_from: Dictionary = {from_coords: Vector2i(-1, -1)}
	# open_set entries: [accumulated_cost, coords]
	var open_set: Array = [[0.0, from_coords]]

	while not open_set.is_empty():
		# Pop lowest-cost entry (linear scan — fine for ≤400 tiles)
		var min_i: int = 0
		for i in range(1, open_set.size()):
			if open_set[i][0] < open_set[min_i][0]:
				min_i = i
		var entry: Array = open_set[min_i]
		open_set.remove_at(min_i)

		var cur_cost: float = entry[0]
		var current: Vector2i = entry[1]

		if current == to_coords:
			break
		if cur_cost > dist.get(current, BIG):
			continue  # stale entry

		for neighbor_tile in tiles[current].neighbors:
			var nc: Vector2i = neighbor_tile.get_coords()
			var is_traversable: bool = neighbor_tile.walkable \
				or (neighbor_tile.has_road and not neighbor_tile.road_under_construction)
			if not is_traversable:
				continue

			# Edge cost matches Builder._physics_process speed formula
			var edge_cost: float
			if neighbor_tile.has_road and not neighbor_tile.road_under_construction:
				edge_cost = road_cost
			else:
				edge_cost = neighbor_tile.cost

			var new_cost: float = cur_cost + edge_cost
			if new_cost < dist.get(nc, BIG):
				dist[nc] = new_cost
				came_from[nc] = current
				open_set.append([new_cost, nc])

	return _reconstruct_path(came_from, to_coords)

func _reconstruct_path(came_from: Dictionary, to_coords: Vector2i) -> Array[Vector2i]:
	if not came_from.has(to_coords):
		return []
	var path: Array[Vector2i] = []
	var step: Vector2i = to_coords
	while step != Vector2i(-1, -1):
		path.append(step)
		step = came_from[step]
	path.reverse()
	return path
