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

# Expansion scoring weights — must sum to 1.0.
const SCORE_W_PROXIMITY:  float = 0.4  # Prefer sites close to existing territory.
const SCORE_W_SAFETY:     float = 0.4  # Prefer sites far from enemy threat.
const SCORE_W_BUILDABLE:  float = 0.2  # Prefer sites with many buildable neighbors.

# Normalisation bounds for scoring.
const SCORE_MAX_DIST:      float = 30.0  # Euclidean upper bound for a 20x20 grid.
const SCORE_MAX_FLOW_COST: float = 40.0  # Upper bound for terrain-weighted path cost.

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


# Finds the best tile for a new base using a weighted scoring system:
#   - Proximity:   prefer sites close to existing own bases (contiguous expansion).
#   - Safety:      prefer sites far from enemy threat, using the flow field's
#                  terrain-weighted path cost to the nearest enemy as the measure.
#   - Buildability: prefer sites with many buildable ring-1 neighbors (more mine slots).
func _find_expansion_tile(grid) -> Tile:
	# Build a forbidden zone: all tiles within (MIN_BASE_SPACING - 1) BFS steps of
	# any owned base, ensuring the new base's ring-1 won't overlap existing rings.
	var forbidden: Dictionary = {}
	var own_base_positions: Array[Vector2] = []
	for structure in structures:
		if structure.structure_type == "base" and not structure.is_under_construction:
			_mark_forbidden_zone(structure.current_tile, MIN_BASE_SPACING - 1, forbidden)
			own_base_positions.append(Vector2(structure.current_tile.x, structure.current_tile.z))

	var best_tile: Tile = null
	var best_score: float = -INF

	for coords in grid.tiles:
		if forbidden.has(coords):
			continue
		var tile: Tile = grid.tiles[coords]
		if not tile.walkable or not tile.buildable or tile.structure != null:
			continue

		var pos := Vector2(tile.x, tile.z)

		# Factor 1 — Proximity: closer to own territory is better.
		var nearest_own: float = INF
		for bp in own_base_positions:
			nearest_own = min(nearest_own, pos.distance_to(bp))
		var score_proximity: float = 1.0 - clamp(nearest_own / SCORE_MAX_DIST, 0.0, 1.0)

		# Factor 2 — Safety: flow_field cost = terrain-weighted distance to nearest
		# enemy (bases + units). Higher cost means farther from the front line.
		# Falls back to 1.0 (maximum safety) if the flow field is not yet populated.
		var flow_cost: float = flow_field.get_flow_cost(tile)
		var score_safety: float = clamp(flow_cost / SCORE_MAX_FLOW_COST, 0.0, 1.0)

		# Factor 3 — Buildability: count terrain-buildable ring-1 neighbors.
		# Predicts future mine capacity regardless of current occupancy.
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
