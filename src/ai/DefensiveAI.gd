# DefensiveAI — Green Team
#
# STRATEGY: Fortify every base with static defenses; no unit production.
#
# Each base is surrounded by exactly one Cannon and as many Mines as fit
# in the remaining neighbor slots. No Drone Factory is ever built, so the
# AI produces no units and holds no front line. Income comes entirely from
# mines; the Cannon (cost 300) requires no ongoing production spend, unlike
# a factory (cost 150) that also consumes resources each time it produces a unit.
#
# Once all owned bases are fully built out, the AI expands to a new base
# and immediately cannons it up before filling with mines.
#
# Expansion scoring is more safety-biased than GreedyAI (0.5 vs 0.4) to
# reflect the lack of units that could otherwise hold contested ground.
#
# Countered by: Long Range AI — artillery outranges the Cannon (8 vs 4 hex)
# and can soften the base from outside cannon range.

class_name DefensiveAI
extends AIPlayer

# How often (seconds) the AI re-evaluates its build queue.
const THINK_INTERVAL: float = 5.0

# Minimum BFS distance a new base must be from any existing owned base.
const MIN_BASE_SPACING: int = 3

# Expansion scoring weights — must sum to 1.0.
# Safety is weighted higher than GreedyAI because there are no units to
# contest enemy advances; only safe sites can be held long-term.
const SCORE_W_PROXIMITY:  float = 0.3
const SCORE_W_SAFETY:     float = 0.5
const SCORE_W_BUILDABLE:  float = 0.2

# Normalisation bounds for scoring.
const SCORE_MAX_DIST:      float = 30.0
const SCORE_MAX_FLOW_COST: float = 40.0

var _map_node: Node3D


func start_turn(p_map_node: Node3D):
	print("DefensiveAI (%s): starting turn." % name)
	_map_node = p_map_node

	if structures.size() == 0:
		push_error("DefensiveAI %d: no base structure found." % id)
		return

	# Do an immediate think so the first decisions happen without waiting.
	_think()

	# Schedule recurring decisions.
	var timer := Timer.new()
	timer.wait_time = THINK_INTERVAL
	timer.autostart = true
	timer.timeout.connect(_think)
	add_child(timer)


# Called every THINK_INTERVAL seconds. Fills bases with cannons/mines,
# then expands if all bases are full.
func _think():
	if not is_instance_valid(_map_node):
		return
	var grid = _map_node.get_node("Grid")
	if not is_instance_valid(grid):
		return

	if _fill_bases():
		return  # Made at least one build decision; wait for next tick.

	# Only expand when all completed bases are full AND no base is still being
	# built. Without the second guard, resources are not yet deducted for ghost
	# bases, so _try_expand() would fire every tick while construction is pending.
	if _all_bases_full() and not _has_base_under_construction():
		_try_expand(grid)


# Iterates owned bases and places a cannon or mine in the first available
# neighbor. Cannon comes first; remaining slots are filled with mines.
# No drone_factory is ever placed — this AI holds no front line.
# Returns true if any structure was successfully placed.
func _fill_bases() -> bool:
	for structure in structures:
		if structure.structure_type != "base":
			continue
		if structure.is_under_construction:
			continue

		var base_tile: Tile = structure.current_tile

		# Ensure each base has exactly one cannon in its ring.
		if not _base_has_cannon(base_tile):
			var tile = _find_free_neighbor(base_tile)
			if tile:
				if place_structure("cannon", tile, _map_node):
					print("DefensiveAI (%s): built cannon near base at %s." % [name, base_tile.get_coords()])
					return true

		# Fill remaining free neighbors with mines.
		var mine_tile = _find_free_neighbor(base_tile)
		if mine_tile:
			if place_structure("mine", mine_tile, _map_node):
				print("DefensiveAI (%s): built mine at %s." % [name, mine_tile.get_coords()])
				return true

	return false


# True if any ring-1 neighbor of base_tile holds a cannon belonging to
# this player.
func _base_has_cannon(base_tile: Tile) -> bool:
	for neighbor in base_tile.neighbors:
		if not is_instance_valid(neighbor):
			continue
		var s = neighbor.structure
		if s and s.player_id == id and s.structure_type == "cannon":
			return true
	return false


# True if any owned base is still under construction.
func _has_base_under_construction() -> bool:
	for structure in structures:
		if structure.structure_type == "base" and structure.is_under_construction:
			return true
	return false


# Attempts to place a new base at the best available expansion site.
func _try_expand(grid) -> void:
	if resources < GameData.STRUCTURE_TYPES["base"]["cost"]:
		return  # Can't afford a base yet; wait for income.

	var best_tile: Tile = _find_expansion_tile(grid)
	if best_tile:
		if place_structure("base", best_tile, _map_node):
			print("DefensiveAI (%s): expanding — new base at %s." % [name, best_tile.get_coords()])
	else:
		print("DefensiveAI (%s): no valid expansion site found." % name)


# Finds the best tile for a new base using a weighted scoring system:
#   - Proximity:    prefer sites close to existing own bases.
#   - Safety:       prefer sites far from enemy threat (higher weight than
#                   GreedyAI — no units to hold contested ground).
#   - Buildability: prefer sites with many buildable ring-1 neighbors.
func _find_expansion_tile(grid) -> Tile:
	var forbidden: Dictionary = {}
	var own_base_positions: Array[Vector2] = []
	for structure in structures:
		if structure.structure_type == "base" and not structure.is_under_construction:
			_mark_forbidden_zone(structure.current_tile, MIN_BASE_SPACING - 1, forbidden)
			own_base_positions.append(Vector2(structure.current_tile.x, structure.current_tile.z))

	var best_tile: Tile = null
	var best_score: float = -INF

	# Factor 1 — Proximity: prefer sites near the centroid of all own bases.
	# Using centroid (not nearest base) prevents chaining expansions in a line:
	# each new base shifts the centroid inward, pulling the next site toward
	# the territory's centre of gravity rather than always extending the chain.
	var centroid := Vector2.ZERO
	for bp in own_base_positions:
		centroid += bp
	if not own_base_positions.is_empty():
		centroid /= float(own_base_positions.size())

	for coords in grid.tiles:
		if forbidden.has(coords):
			continue
		var tile: Tile = grid.tiles[coords]
		if not tile.walkable or not tile.buildable or tile.structure != null:
			continue

		var pos := Vector2(tile.x, tile.z)

		var score_proximity: float = 1.0 - clamp(pos.distance_to(centroid) / SCORE_MAX_DIST, 0.0, 1.0)

		# Factor 2 — Safety: flow_field cost = terrain-weighted distance to
		# nearest enemy. Higher cost means farther from the front line.
		var flow_cost: float = flow_field.get_flow_cost(tile)
		var score_safety: float = clamp(flow_cost / SCORE_MAX_FLOW_COST, 0.0, 1.0)

		# Factor 3 — Buildability: count terrain-buildable ring-1 neighbors.
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
