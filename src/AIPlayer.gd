# AIPlayer — Base class for all AI-controlled players.
#
# Subclasses in src/ai/ override start_turn() to implement distinct strategies:
#   - GreedyAI    (Blue/Orange): economy focus, mines first
#   - DefensiveAI (Green):       cannon at every base
#   - LongRangeAI (Yellow):      artillery behind the front line
#   - AggressiveAI (Purple):     immediate military rush
#
# This base implementation provides a safe fallback: build a drone factory
# next to the base. Subclasses should call their own full logic and do NOT
# need to call super().

class_name AIPlayer
extends Player

# Called by Game.gd after the base structure has been placed.
# Override in subclasses to implement AI-specific strategy.
func start_turn(p_map_node: Node3D):
	print("AIPlayer %d (%s): using base fallback strategy." % [id, name])

	if structures.size() == 0:
		push_error("AIPlayer %d: Base structure not found." % id)
		return

	var base_tile: Tile = structures[0].current_tile

	for neighbor_tile in base_tile.neighbors:
		if is_instance_valid(neighbor_tile) and neighbor_tile.walkable and neighbor_tile.structure == null:
			var success = place_structure("drone_factory", neighbor_tile, p_map_node)
			if success:
				print("AIPlayer %d built drone_factory at %s." % [id, neighbor_tile.get_coords()])
			return

	push_error("AIPlayer %d: no free tile next to base for drone_factory." % id)


# --- Shared spatial utilities (available to all subclasses) ---

# Returns the first ring-1 neighbor that is walkable, buildable, and free.
func _find_free_neighbor(center_tile: Tile) -> Tile:
	for neighbor in center_tile.neighbors:
		if not is_instance_valid(neighbor):
			continue
		if neighbor.walkable and neighbor.buildable and neighbor.structure == null:
			return neighbor
	return null


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


# True if any ring-1 neighbor of base_tile holds a tank_factory belonging
# to this player.
func _base_has_tank_factory(base_tile: Tile) -> bool:
	for neighbor in base_tile.neighbors:
		if not is_instance_valid(neighbor):
			continue
		var s = neighbor.structure
		if s and s.player_id == id and s.structure_type == "tank_factory":
			return true
	return false


# Counts how many owned structures of `type` are adjacent to base_tile.
func _count_type_near_base(base_tile: Tile, type: String) -> int:
	var count: int = 0
	for neighbor in base_tile.neighbors:
		if not is_instance_valid(neighbor):
			continue
		var s = neighbor.structure
		if s and s.player_id == id and s.structure_type == type:
			count += 1
	return count


# Counts all owned (non-under-construction) structures of the given type.
func _count_structure_type(type: String) -> int:
	var count: int = 0
	for s in structures:
		if s.structure_type == type and not s.is_under_construction:
			count += 1
	return count


# Returns "drone_factory" or "tank_factory" based on which type this player
# currently owns fewer of. Drones are preferred when counts are equal so the
# first factory built is always infantry (to establish the frontline).
func _choose_factory_type() -> String:
	var drones := _count_structure_type("drone_factory")
	var tanks  := _count_structure_type("tank_factory")
	return "drone_factory" if drones <= tanks else "tank_factory"


# True if any owned base is still under construction.
func _has_base_under_construction() -> bool:
	for structure in structures:
		if structure.structure_type == "base" and structure.is_under_construction:
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
