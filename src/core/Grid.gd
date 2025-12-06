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
	
	# Calculate a boundary margin based on half of the tile spacing to ensure the camera center
	# always sees the edge tiles fully.
	var CAMERA_MARGIN_X = X_SPACING * 0.5
	var CAMERA_MARGIN_Z = Z_SPACING * 0.5

	# Calculate max coordinate for tile centers:
	# X_MAX_CENTER: Center of the right-most tile (which is offset by 0.5 in an odd row, max x=W-1)
	var X_MAX_CENTER = (float(W) - 0.5) * X_SPACING
	# Z_MAX_CENTER: Center of the bottom-most tile (max z=H-1)
	var Z_MAX_CENTER = float(H - 1) * Z_SPACING
	
	# Apply margins to define the camera bounds (camera center position)
	# The X and Z MIN are 0 (center of tile 0,0) minus the margin.
	MAP_X_MIN = 0.0 - CAMERA_MARGIN_X
	MAP_X_MAX = X_MAX_CENTER + CAMERA_MARGIN_X
	MAP_Z_MIN = 0.0 - CAMERA_MARGIN_Z
	MAP_Z_MAX = Z_MAX_CENTER + CAMERA_MARGIN_Z

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
		var tile_data: Tile = tiles[coords]
		var tile_node: Node3D = tile_data.node
		node_to_coords[tile_node] = coords

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
