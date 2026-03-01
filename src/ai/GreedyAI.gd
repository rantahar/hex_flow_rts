# GreedyAI — Blue Team / Orange Team
#
# STRATEGY: Economic dominance through mine saturation and base expansion.
#
# Each base is surrounded by exactly one Drone Factory and as many Mines as
# fit in the remaining neighbor slots. Once all owned bases are fully built
# out, the AI expands to a new base chosen to be:
#   - at least 3 hex tiles away from every existing owned base (so the two
#     exclusion zones don't overlap and both bases can fill their rings)
#   - as far as possible from the enemy front line (enemy base centroid)
#
# This compounds over time: each new base adds 5+ mines worth of income,
# funding even more factories and bases in an economic snowball.
#
# Countered by: Aggressive AI — a rush arrives before the economy peaks.
# Apply early pressure to Blue to deny the snowball before it starts.

class_name GreedyAI
extends AIPlayer

# How often (seconds) the AI re-evaluates its build queue.
const THINK_INTERVAL: float = 5.0

# Minimum BFS distance a new base must be from any existing owned base.
# 3 ensures both bases can fill their full ring-1 without overlap.
const MIN_BASE_SPACING: int = 3

var _map_node: Node3D


func start_turn(p_map_node: Node3D):
	print("GreedyAI (%s): starting turn." % name)
	_map_node = p_map_node

	if structures.size() == 0:
		push_error("GreedyAI %d: no base structure found." % id)
		return

	# Do an immediate think so the first decisions happen without waiting.
	_think()

	# Schedule recurring decisions.
	var timer := Timer.new()
	timer.wait_time = THINK_INTERVAL
	timer.autostart = true
	timer.timeout.connect(_think)
	add_child(timer)


# Called every THINK_INTERVAL seconds. Fills bases with mines/factories,
# then expands if all bases are full.
func _think():
	if not is_instance_valid(_map_node):
		return
	var grid = _map_node.get_node("Grid")
	if not is_instance_valid(grid):
		return

	if _fill_bases():
		return  # Made at least one build decision; wait for next tick.

	# All bases are fully built out — try to expand.
	if _all_bases_full():
		_try_expand(grid)


# Iterates owned bases and places a drone_factory or mine in the first
# available neighbor. Returns true if any structure was successfully placed
# (so the caller knows to stop for this tick).
func _fill_bases() -> bool:
	for structure in structures:
		if structure.structure_type != "base":
			continue
		if structure.is_under_construction:
			continue

		var base_tile: Tile = structure.current_tile

		# Ensure each base has exactly one drone factory in its ring.
		if not _base_has_factory(base_tile):
			var tile = _find_free_neighbor(base_tile)
			if tile:
				if place_structure("drone_factory", tile, _map_node):
					print("GreedyAI (%s): built drone_factory near base at %s." % [name, base_tile.get_coords()])
					return true

		# Fill remaining free neighbors with mines.
		var mine_tile = _find_free_neighbor(base_tile)
		if mine_tile:
			if place_structure("mine", mine_tile, _map_node):
				print("GreedyAI (%s): built mine at %s." % [name, mine_tile.get_coords()])
				return true

	return false


# Returns true if every non-under-construction base has no free buildable
# walkable neighbors remaining.
func _all_bases_full() -> bool:
	for structure in structures:
		if structure.structure_type != "base":
			continue
		if structure.is_under_construction:
			continue
		if not _is_base_full(structure.current_tile):
			return false
	return true


# True if all ring-1 neighbors of base_tile are either non-buildable,
# non-walkable, or already occupied.
func _is_base_full(base_tile: Tile) -> bool:
	return _find_free_neighbor(base_tile) == null


# True if any ring-1 neighbor of base_tile holds a drone_factory belonging
# to this player.
func _base_has_factory(base_tile: Tile) -> bool:
	for neighbor in base_tile.neighbors:
		if not is_instance_valid(neighbor):
			continue
		var s = neighbor.structure
		if s and s.player_id == id and s.structure_type == "drone_factory":
			return true
	return false


# Returns the first ring-1 neighbor that is walkable, buildable, and free.
func _find_free_neighbor(center_tile: Tile) -> Tile:
	for neighbor in center_tile.neighbors:
		if not is_instance_valid(neighbor):
			continue
		if neighbor.walkable and neighbor.buildable and neighbor.structure == null:
			return neighbor
	return null


# Attempts to place a new base at the best available expansion site.
func _try_expand(grid) -> void:
	if resources < GameData.STRUCTURE_TYPES["base"]["cost"]:
		return  # Can't afford a base yet; wait for income.

	var best_tile: Tile = _find_expansion_tile(grid)
	if best_tile:
		if place_structure("base", best_tile, _map_node):
			print("GreedyAI (%s): expanding — new base at %s." % [name, best_tile.get_coords()])
	else:
		print("GreedyAI (%s): no valid expansion site found." % name)


# Finds the best tile for a new base:
#   1. At least MIN_BASE_SPACING hex from any owned base (BFS exclusion).
#   2. Highest distance from the enemy centroid (farthest from front line).
func _find_expansion_tile(grid) -> Tile:
	# Build a forbidden set: all tiles within (MIN_BASE_SPACING - 1) steps of
	# any owned base.
	var forbidden: Dictionary = {}
	for structure in structures:
		if structure.structure_type == "base" and not structure.is_under_construction:
			_mark_forbidden_zone(structure.current_tile, MIN_BASE_SPACING - 1, forbidden)

	var enemy_centroid: Vector2 = _get_enemy_centroid()

	var best_tile: Tile = null
	var best_score: float = -INF

	for coords in grid.tiles:
		if forbidden.has(coords):
			continue
		var tile: Tile = grid.tiles[coords]
		if not tile.walkable or not tile.buildable or tile.structure != null:
			continue

		# Score = distance from enemy centroid (farther = safer expansion).
		var pos := Vector2(tile.x, tile.z)
		var score: float = pos.distance_to(enemy_centroid)
		if score > best_score:
			best_score = score
			best_tile = tile

	return best_tile


# BFS from center_tile outward up to `radius` steps, marking all visited
# tile coords in `dict`.
func _mark_forbidden_zone(center_tile: Tile, radius: int, dict: Dictionary) -> void:
	var queue: Array = [[center_tile, 0]]
	var visited: Dictionary = {center_tile.get_coords(): true}

	while not queue.is_empty():
		var entry: Array = queue.pop_front()
		var tile: Tile = entry[0]
		var dist: int = entry[1]

		dict[tile.get_coords()] = true

		if dist >= radius:
			continue

		for neighbor in tile.neighbors:
			if not is_instance_valid(neighbor):
				continue
			var nc: Vector2i = neighbor.get_coords()
			if not visited.has(nc):
				visited[nc] = true
				queue.append([neighbor, dist + 1])


# Returns the average grid position (Vector2) of all enemy base tiles.
# Falls back to a far-away point if no enemy bases exist.
func _get_enemy_centroid() -> Vector2:
	var game = get_parent()
	if not is_instance_valid(game):
		return Vector2(1000.0, 1000.0)

	var total := Vector2.ZERO
	var count: int = 0

	for player in game.players:
		if not is_instance_valid(player) or player.id == id:
			continue
		for structure in player.structures:
			if structure.structure_type == "base" and not structure.is_under_construction:
				total += Vector2(structure.current_tile.x, structure.current_tile.z)
				count += 1

	if count == 0:
		return Vector2(1000.0, 1000.0)  # No known enemies; pick any far tile.

	return total / float(count)
