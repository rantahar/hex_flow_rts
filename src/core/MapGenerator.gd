extends Node3D

class_name MapGenerator

const GameData = preload("res://data/game_data.gd")
const GameConfig = preload("res://data/game_config.gd")
const TILE_SCENE = preload("res://src/core/tile.tscn")
const TILE_SIMPLE_SCENE = preload("res://src/core/tile_simple.tscn")

var map_width: int = GameData.MAP_WIDTH
var map_height: int = GameData.MAP_HEIGHT

@onready var grid: Grid = get_parent().get_node("Grid")

var generated_tiles: Dictionary = {}

# Built in pre-pass before any scene nodes are created (Vector2i -> String tile key)
var type_map: Dictionary = {}

# Chosen spawn coordinates, exposed for Game.gd to read after generate_map()
var spawn_coords: Array[Vector2i] = []

const MAP_TYPES: Array = ["island", "coast", "river", "lake", "open"]


func generate_map() -> void:
	randomize()  # Ensure a fresh seed each run
	generated_tiles.clear()
	type_map.clear()
	spawn_coords.clear()

	for child in get_children():
		child.queue_free()

	_build_type_map()

	for coords in type_map:
		_instantiate_tile(coords, type_map[coords])

	_update_tile_heights()


# ─── Type-map construction ────────────────────────────────────────────────────

func _build_type_map() -> void:
	var map_type: String = _choose_map_type()
	print("[MapGen] Map type: %s" % map_type)

	_pre_place_water(map_type)
	print("[MapGen] Pre-placed water tiles: %d" % type_map.size())
	if randf() < 0.5:
		print("[MapGen] Adding mountain range")
		_place_mountain_range()
	_fill_remaining_tiles()
	_place_player_spawns()


func _choose_map_type() -> String:
	return MAP_TYPES[randi() % MAP_TYPES.size()]


func _pre_place_water(map_type: String) -> void:
	var cx: int = map_width >> 1
	var cz: int = map_height >> 1

	match map_type:
		"island":
			for z in range(map_height):
				for x in range(map_width):
					if x == 0 or x == map_width - 1 or z == 0 or z == map_height - 1:
						type_map[Vector2i(x, z)] = "water"

		"coast":
			var edge: int = randi() % 4  # 0=N, 1=S, 2=E, 3=W
			for z in range(map_height):
				for x in range(map_width):
					var on_edge: bool = false
					match edge:
						0: on_edge = z < GameConfig.MAP_COAST_EDGE_WIDTH
						1: on_edge = z >= map_height - GameConfig.MAP_COAST_EDGE_WIDTH
						2: on_edge = x >= map_width - GameConfig.MAP_COAST_EDGE_WIDTH
						3: on_edge = x < GameConfig.MAP_COAST_EDGE_WIDTH
					if on_edge:
						type_map[Vector2i(x, z)] = "water"

		"river":
			var rx: int = cx
			for z in range(map_height):
				# Wobble river left or right with 33% probability each direction
				var roll: int = randi() % 3
				if roll == 0:
					rx = clampi(rx - 1, 1, map_width - 2)
				elif roll == 1:
					rx = clampi(rx + 1, 1, map_width - 2)
				type_map[Vector2i(rx, z)] = "water"

		"lake":
			var center = Vector2i(cx, cz)
			for z in range(map_height):
				for x in range(map_width):
					if _hex_distance(Vector2i(x, z), center) <= GameConfig.MAP_LAKE_RADIUS:
						type_map[Vector2i(x, z)] = "water"

		"open":
			pass  # No pre-placed water


func _place_mountain_range() -> void:
	# Collect non-water candidate start tiles
	var candidates: Array[Vector2i] = []
	for z in range(map_height):
		for x in range(map_width):
			var c = Vector2i(x, z)
			if not type_map.has(c):
				candidates.append(c)
	if candidates.is_empty():
		return

	candidates.shuffle()
	var pos: Vector2i = candidates[0]

	# Pick a preferred direction index (one of 6)
	var dir_idx: int = randi() % 6
	var length: int = randi_range(GameConfig.MAP_MOUNTAIN_MIN_LENGTH, GameConfig.MAP_MOUNTAIN_MAX_LENGTH)

	for _i in range(length):
		if not type_map.has(pos):
			type_map[pos] = "mountain"

		# Advance to neighbor in preferred direction (with 30% chance of deviation)
		var offsets: Array[Vector2i]
		if pos.y % 2 != 0:
			offsets = Grid.ODD_R_NEIGHBOR_OFFSETS_ODD
		else:
			offsets = Grid.ODD_R_NEIGHBOR_OFFSETS_EVEN

		if randf() < GameConfig.MAP_MOUNTAIN_DEVIATION_CHANCE:
			var deviation: int = -1 if randf() < 0.5 else 1
			dir_idx = (dir_idx + deviation) % 6
			if dir_idx < 0:
				dir_idx += 6

		var next: Vector2i = pos + offsets[dir_idx]
		if next.x < 0 or next.x >= map_width or next.y < 0 or next.y >= map_height:
			break
		pos = next


func _fill_remaining_tiles() -> void:
	# Build list of all unassigned coords and shuffle for isotropic fill
	var unassigned: Array[Vector2i] = []
	for z in range(map_height):
		for x in range(map_width):
			var c = Vector2i(x, z)
			if not type_map.has(c):
				unassigned.append(c)
	unassigned.shuffle()

	for coords in unassigned:
		# Base pool from GameData weights
		var pool: Array[String] = []
		for key in GameData.TILES:
			var w: int = GameData.TILES[key].get("weight", 1)
			for _i in range(w):
				pool.append(key)

		# Neighbor influence: each assigned neighbor adds its type to bias clustering
		for neighbor in _get_neighbor_coords(coords):
			if type_map.has(neighbor):
				for i in range(GameConfig.MAP_NEIGHBOR_INFLUENCE_WEIGHT):
					pool.append(type_map[neighbor])

		type_map[coords] = pool.pick_random()


func _place_player_spawns() -> void:
	var num_players: int = GameData.PLAYER_CONFIGS.size()
	var min_dist: int = GameConfig.MAP_SPAWN_MIN_DISTANCE

	while min_dist >= 2:
		var grass_tiles: Array[Vector2i] = []
		for coords in type_map:
			if type_map[coords] == "grass":
				grass_tiles.append(coords)
		grass_tiles.shuffle()

		var chosen: Array[Vector2i] = []
		for candidate in grass_tiles:
			var far_enough: bool = true
			for existing in chosen:
				if _hex_distance(candidate, existing) < min_dist:
					far_enough = false
					break
			if far_enough:
				chosen.append(candidate)
			if chosen.size() == num_players:
				break

		if chosen.size() == num_players:
			spawn_coords = chosen
			break

		min_dist -= 1

	if spawn_coords.size() < num_players:
		push_error("MapGenerator: Could not find valid spawn positions for all players.")
		# Fallback: use corner-ish positions
		spawn_coords.append(Vector2i(2, 2))
		if num_players > 1:
			spawn_coords.append(Vector2i(map_width - 3, map_height - 3))

	# Clear adjacent mountains/water so spawns are safe to land on
	for spawn in spawn_coords:
		for neighbor in _get_neighbor_coords(spawn):
			var t: String = type_map.get(neighbor, "")
			if t == "mountain" or t == "water":
				type_map[neighbor] = "grass" if randf() < 0.5 else "dirt"


# ─── Tile instantiation ───────────────────────────────────────────────────────

func _instantiate_tile(coords: Vector2i, tile_key: String) -> void:
	var x: int = coords.x
	var z: int = coords.y

	var pos_x: float = float(x) * Grid.X_SPACING * GameConfig.HEX_SCALE
	var pos_z: float = float(z) * Grid.Z_SPACING * GameConfig.HEX_SCALE
	if z % 2 != 0:
		pos_x += (Grid.X_SPACING * GameConfig.HEX_SCALE) / 2.0

	var tile_pos := Vector3(pos_x, 0, pos_z)

	var tile_def: Dictionary = GameData.TILES[tile_key]
	var selected_mesh: Mesh = load(tile_def.mesh_path)
	if not selected_mesh:
		push_error("MapGenerator: Failed to load mesh: %s" % tile_def.mesh_path)
		return

	var tile_root: Node3D
	if tile_def.buildable:
		var csg_tile = TILE_SCENE.instantiate() as CSGMesh3D
		csg_tile.name = "Hex_%d_%d" % [x, z]
		csg_tile.position = tile_pos
		csg_tile.mesh = selected_mesh
		tile_root = csg_tile
	else:
		var mesh_tile = TILE_SIMPLE_SCENE.instantiate() as MeshInstance3D
		mesh_tile.name = "Hex_%d_%d" % [x, z]
		mesh_tile.position = tile_pos
		mesh_tile.mesh = selected_mesh
		mesh_tile.create_trimesh_collision()
		tile_root = mesh_tile

	tile_root.scale = Vector3.ONE * GameConfig.HEX_SCALE * 0.9
	tile_root.rotation_degrees.y = 0.0
	add_child(tile_root)

	var tile_data: Tile = tile_root as Tile
	tile_data.x = x
	tile_data.z = z
	tile_data.world_pos = tile_pos
	tile_data.walkable = tile_def.walkable
	tile_data.cost = tile_def.walk_cost
	tile_data.buildable = tile_def.buildable

	generated_tiles[coords] = tile_data


func _update_tile_heights() -> void:
	var map_node = get_parent()
	if not is_instance_valid(map_node):
		push_error("MapGenerator: Could not find parent Map node")
		return

	for coords in generated_tiles:
		var tile: Tile = generated_tiles[coords]
		if not is_instance_valid(tile):
			continue
		var planar_pos = Vector3(tile.world_pos.x, 0, tile.world_pos.z)
		tile.world_pos.y = map_node.get_height_at_world_pos(planar_pos)


func get_tiles() -> Dictionary:
	return generated_tiles


# ─── Helpers ─────────────────────────────────────────────────────────────────

func _get_neighbor_coords(coords: Vector2i) -> Array[Vector2i]:
	var offsets: Array[Vector2i]
	if coords.y % 2 != 0:
		offsets = Grid.ODD_R_NEIGHBOR_OFFSETS_ODD
	else:
		offsets = Grid.ODD_R_NEIGHBOR_OFFSETS_EVEN

	var result: Array[Vector2i] = []
	for offset in offsets:
		var neighbor = coords + offset
		if neighbor.x >= 0 and neighbor.x < map_width and neighbor.y >= 0 and neighbor.y < map_height:
			result.append(neighbor)
	return result


# Convert Odd-R offset coordinates to cube coordinates and return hex distance.
func _hex_distance(a: Vector2i, b: Vector2i) -> int:
	var aq: int = a.x - ((a.y - (a.y & 1)) >> 1)
	var ar: int = a.y
	var bq: int = b.x - ((b.y - (b.y & 1)) >> 1)
	var br: int = b.y
	return maxi(absi(aq - bq), maxi(absi(ar - br), absi((-aq - ar) - (-bq - br))))
