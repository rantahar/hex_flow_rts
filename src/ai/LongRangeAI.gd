# LongRangeAI — Yellow Team
#
# STRATEGY: Area denial through artillery positioned behind the front line.
#
# Artillery has the longest attack range in the game (8 hex, AoE radius 1)
# and deals massive damage per shot. The Long Range AI exploits this by
# placing artillery behind the midpoint between own and enemy bases, where
# enemy units cannot easily reach it while it bombards approaching formations.
#
# This makes Yellow hard to push into — infantry gets shredded before it
# closes to melee range, and even tanks take heavy attrition.
#
# Build order:
#   1. Drone Factory — infantry screen to protect artillery from flankers
#   2. Mines          — fill remaining base slots for sustained income
#   3. Artillery      — placed 3 hexes behind the battlefield midpoint
#   4. Expand         — new base once all slots are full
#
# Countered by: Aggressive AI — a fast rush can close the distance before
# artillery fire is decisive. Players should flank around the kill zone
# or commit massed infantry to overwhelm the screen units quickly.

class_name LongRangeAI
extends AIPlayer

# How often (seconds) the AI re-evaluates its build queue.
const THINK_INTERVAL: float = 5.0

# Minimum BFS distance a new base must be from any existing owned base.
const MIN_BASE_SPACING: int = 3

# Maximum total artillery pieces (including under-construction).
const MAX_ARTILLERY: int = 4

# How many hexes behind the battlefield midpoint to place artillery.
const ARTY_SETBACK: float = 3.0

# Minimum flow field cost for an artillery tile — prevents placing in a hot zone.
# flow_field cost is terrain-weighted distance to nearest enemy; lower = closer.
const MIN_ARTY_FLOW_COST: float = 6.0

# Expansion scoring weights — must sum to 1.0.
# Safety is weighted higher than GreedyAI because there are no units to
# contest enemy advances without the artillery screen.
const SCORE_W_PROXIMITY:  float = 0.3
const SCORE_W_SAFETY:     float = 0.5
const SCORE_W_BUILDABLE:  float = 0.2

# Normalisation bounds for scoring.
const SCORE_MAX_DIST:      float = 30.0
const SCORE_MAX_FLOW_COST: float = 40.0

var _map_node: Node3D


func start_turn(p_map_node: Node3D):
	print("LongRangeAI (%s): starting turn — artillery strategy." % name)
	_map_node = p_map_node

	if structures.size() == 0:
		push_error("LongRangeAI %d: no base structure found." % id)
		return

	# Immediate first think so decisions happen without waiting.
	_think()

	# Schedule recurring decisions.
	var timer := Timer.new()
	timer.wait_time = THINK_INTERVAL
	timer.autostart = true
	timer.timeout.connect(_think)
	add_child(timer)


# Called every THINK_INTERVAL seconds. Fills bases, then places artillery,
# then expands if all bases are full.
func _think():
	if not is_instance_valid(_map_node):
		return
	var grid = _map_node.get_node("Grid")
	if not is_instance_valid(grid):
		return

	# Priority 1: fill all bases with a factory and mines.
	if _fill_bases():
		return

	# Priority 2: place more artillery if below cap.
	if _all_bases_full():
		_try_place_artillery(grid)

	# Priority 3: expand when all bases are full and none is pending construction.
	if _all_bases_full() and not _has_base_under_construction():
		_try_expand(grid)


# Iterates owned bases and places a drone_factory or mine in the first available
# neighbor. Returns true if any structure was successfully placed.
func _fill_bases() -> bool:
	for structure in structures:
		if structure.structure_type != "base":
			continue
		if structure.is_under_construction:
			continue

		var base_tile: Tile = structure.current_tile

		# Ensure each completed base has exactly one drone_factory for infantry screening.
		if not _base_has_factory(base_tile):
			var tile = _find_free_neighbor(base_tile)
			if tile:
				if place_structure("drone_factory", tile, _map_node):
					print("LongRangeAI (%s): built drone_factory near base at %s." % [name, base_tile.get_coords()])
					return true

		# Fill remaining free neighbors with mines.
		var mine_tile = _find_free_neighbor(base_tile)
		if mine_tile:
			if place_structure("mine", mine_tile, _map_node):
				print("LongRangeAI (%s): built mine at %s." % [name, mine_tile.get_coords()])
				return true

	return false


# Places one artillery piece behind the frontline if below MAX_ARTILLERY and
# resources permit.
func _try_place_artillery(grid) -> void:
	# Count all artillery — including under-construction — to avoid exceeding cap.
	var arty_count: int = 0
	for s in structures:
		if s.structure_type == "artillery":
			arty_count += 1

	if arty_count >= MAX_ARTILLERY:
		return

	if resources < GameData.STRUCTURE_TYPES["artillery"]["cost"]:
		return

	var tile: Tile = _find_artillery_tile(grid)
	if tile:
		if place_structure("artillery", tile, _map_node):
			print("LongRangeAI (%s): placed artillery at %s." % [name, tile.get_coords()])
	else:
		print("LongRangeAI (%s): no valid artillery placement found." % name)


# Finds the best tile for an artillery piece.
#
# The ideal position is the midpoint between own base centroid and enemy
# centroid, pulled ARTY_SETBACK hexes back toward own territory. Among all
# candidate tiles, the one closest to that ideal point is chosen.
#
# A safety guard rejects tiles with flow_field cost below MIN_ARTY_FLOW_COST
# (i.e. too close to enemy forces).
func _find_artillery_tile(grid) -> Tile:
	# Compute own base centroid.
	var own_centroid := Vector2.ZERO
	var own_count: int = 0
	for s in structures:
		if s.structure_type == "base" and not s.is_under_construction:
			own_centroid += Vector2(s.current_tile.x, s.current_tile.z)
			own_count += 1
	if own_count == 0:
		return null
	own_centroid /= float(own_count)

	var enemy_centroid: Vector2 = _get_enemy_centroid()

	# Ideal point: midpoint biased ARTY_SETBACK hexes toward own territory.
	var midpoint: Vector2 = (own_centroid + enemy_centroid) * 0.5
	var dir_to_own: Vector2 = (own_centroid - enemy_centroid).normalized()
	var ideal: Vector2 = midpoint + dir_to_own * ARTY_SETBACK

	var best_tile: Tile = null
	var best_dist: float = INF

	for coords in grid.tiles:
		var tile: Tile = grid.tiles[coords]
		if not tile.walkable or not tile.buildable or tile.structure != null:
			continue

		# Safety guard: skip tiles too close to enemy.
		var flow_cost: float = flow_field.get_flow_cost(tile)
		if flow_cost < MIN_ARTY_FLOW_COST:
			continue

		var dist: float = Vector2(tile.x, tile.z).distance_to(ideal)
		if dist < best_dist:
			best_dist = dist
			best_tile = tile

	return best_tile


# Attempts to place a new base at the best available expansion site.
func _try_expand(grid) -> void:
	if resources < GameData.STRUCTURE_TYPES["base"]["cost"]:
		return

	var best_tile: Tile = _find_expansion_tile(grid)
	if best_tile:
		if place_structure("base", best_tile, _map_node):
			print("LongRangeAI (%s): expanding — new base at %s." % [name, best_tile.get_coords()])
	else:
		print("LongRangeAI (%s): no valid expansion site found." % name)


# Finds the best tile for a new base using a weighted scoring system:
#   - Proximity:    prefer sites near the centroid of all own bases.
#   - Safety:       prefer sites far from enemy threat (higher weight —
#                   no front-line units to hold contested ground).
#   - Buildability: prefer sites with many buildable ring-1 neighbors.
func _find_expansion_tile(grid) -> Tile:
	var forbidden: Dictionary = {}
	var own_base_positions: Array[Vector2] = []
	for structure in structures:
		if structure.structure_type == "base" and not structure.is_under_construction:
			_mark_forbidden_zone(structure.current_tile, MIN_BASE_SPACING - 1, forbidden)
			own_base_positions.append(Vector2(structure.current_tile.x, structure.current_tile.z))

	var centroid := Vector2.ZERO
	for bp in own_base_positions:
		centroid += bp
	if not own_base_positions.is_empty():
		centroid /= float(own_base_positions.size())

	var best_tile: Tile = null
	var best_score: float = -INF

	for coords in grid.tiles:
		if forbidden.has(coords):
			continue
		var tile: Tile = grid.tiles[coords]
		if not tile.walkable or not tile.buildable or tile.structure != null:
			continue

		var pos := Vector2(tile.x, tile.z)

		var score_proximity: float = 1.0 - clamp(pos.distance_to(centroid) / SCORE_MAX_DIST, 0.0, 1.0)

		var flow_cost: float = flow_field.get_flow_cost(tile)
		var score_safety: float = clamp(flow_cost / SCORE_MAX_FLOW_COST, 0.0, 1.0)

		var buildable_count: int = 0
		for neighbor in tile.neighbors:
			if is_instance_valid(neighbor) and neighbor.buildable:
				buildable_count += 1
		var score_buildable := buildable_count / 6.0

		var total: float = SCORE_W_PROXIMITY * score_proximity \
				   + SCORE_W_SAFETY    * score_safety \
				   + SCORE_W_BUILDABLE * score_buildable

		if total > best_score:
			best_score = total
			best_tile = tile

	return best_tile
