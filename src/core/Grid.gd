extends Node
class_name Grid

# Hex grid geometry constants
const HEX_SCALE: float = 0.6
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
	Performs a Breadth-First Search (BFS) to find all walkable tiles
	reachable from the starting coordinate.
	A tile is reachable if it is walkable and has a finite cost.
	
	Arguments:
	- start_coord (Vector2i): The grid coordinate (x, z) to start the search from.
	
	Returns:
	- Array[Vector2i]: An array of coordinates for all reachable tiles.
	"""
	var start_tile: Tile = get_tile_by_coords(start_coord)
	
	# Using Godot's float infinity constant defined in Tile.gd
	# We rely on Tile being preloaded implicitly by MapGenerator or similar,
	# but for explicit type hints here, we need it.
	# Since Tile.gd uses `const Grid = preload("res://src/core/Grid.gd")`,
	# Grid.gd should probably preload Tile.gd too if we want to use its INF constant,
	# but `Tile` is already typed in `get_tile_by_coords` which returns a Tile.
	# For simplicity, I'll redefine INF if it's not globally available or accessible.
	# Wait, `get_tile_by_coords` is dynamically typed, but the tile itself is a typed class.
	# I'll use a direct float value as a fallback, or assume the Tile object carries the necessary info.
	# Tile.gd: const INF: float = 1e20
	const INF: float = 1e20 # Defining it here to avoid dependency on Tile.gd constants
	
	if start_tile == null or not start_tile.walkable or start_tile.cost >= INF:
		return [] # Start tile is invalid or blocked/unreachable
		
	var queue: Array = [start_tile]
	var visited: Dictionary = {start_coord: true} # Using coordinates for tracking
	var reachable_coords: Array[Vector2i] = [start_coord]
	
	while not queue.is_empty():
		var current_tile: Tile = queue.pop_front()
		
		# Current tile neighbors are already Tile objects
		for neighbor_tile in current_tile.neighbors:
			var neighbor_coord: Vector2i = neighbor_tile.get_coords()
			
			# Check reachability criteria: walkable and finite cost
			# We also check if the tile is known to the grid (by checking tiles.has(coord))
			# but since `current_tile.neighbors` only contains tiles known to the grid,
			# we only need to check walkability/cost and visited status.
			if neighbor_tile.walkable and neighbor_tile.cost < INF and not visited.has(neighbor_coord):
				visited[neighbor_coord] = true
				reachable_coords.append(neighbor_coord)
				queue.append(neighbor_tile)
				
	return reachable_coords

func find_path(from_coords: Vector2i, to_coords: Vector2i) -> Array[Vector2i]:
	"""
	BFS point-to-point pathfinding. Traverses all tiles including non-walkable ones
	(since roads can be built on water/mountains). Returns ordered path from start to end.
	Returns empty array if no path exists.
	"""
	if not tiles.has(from_coords) or not tiles.has(to_coords):
		return []
	if from_coords == to_coords:
		return [from_coords]

	var queue: Array = [from_coords]
	var came_from: Dictionary = {from_coords: Vector2i(-1, -1)}

	while not queue.is_empty():
		var current: Vector2i = queue.pop_front()
		if current == to_coords:
			break

		var current_tile: Tile = tiles[current]
		for neighbor_tile in current_tile.neighbors:
			var neighbor_coord: Vector2i = neighbor_tile.get_coords()
			if not came_from.has(neighbor_coord):
				came_from[neighbor_coord] = current
				queue.append(neighbor_coord)

	# Reconstruct path
	if not came_from.has(to_coords):
		return []

	var path: Array[Vector2i] = []
	var step: Vector2i = to_coords
	while step != Vector2i(-1, -1):
		path.append(step)
		step = came_from[step]
	path.reverse()
	return path
