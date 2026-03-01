# AggressiveAI — Purple Team
#
# STRATEGY: Early military rush before opponents can establish economy.
#
# The Aggressive AI sacrifices long-term economic growth for immediate combat
# power. Starting resources are burned on factories first; mines follow to
# sustain ongoing production.
#
# Build order — Base 1:
#   1. Drone Factory × 2  — both up front to maximise infantry output
#   2. Mine × 4           — sustains both drone factories (base+4 mines = 30/sec)
#
# Build order — Base 2 (expanded toward the enemy):
#   1. Tank Factory       — heavy assault units
#   2. Mine × 3           — sustains tank factory (base+3 mines = 25/sec)
#   3. Drone Factory      — fill remaining slots with more infantry
#
# The second base is positioned aggressively — scored toward the enemy front
# rather than away from it (unlike GreedyAI). Max 2 bases total.
#
# Countered by: Defensive AI — a Cannon next to the enemy base chews through
# the incoming rush. Players should build static defenses early when facing
# Purple, then counter-attack once the rush is spent.

class_name AggressiveAI
extends AIPlayer

const THINK_INTERVAL: float = 5.0
const MAX_BASES: int = 2

const SCORE_W_PROXIMITY:  float = 0.3
const SCORE_W_AGGRESSION: float = 0.5
const SCORE_W_BUILDABLE:  float = 0.2
const SCORE_MAX_DIST:     float = 30.0
const FORBIDDEN_RADIUS:   int   = 2  # Smaller than GreedyAI; allow forward bases.

var _map_node: Node3D


func start_turn(p_map_node: Node3D):
	print("AggressiveAI (%s): starting turn — rush build order." % name)
	_map_node = p_map_node

	if structures.size() == 0:
		push_error("AggressiveAI %d: no base structure found." % id)
		return

	_think()

	var timer := Timer.new()
	timer.wait_time = THINK_INTERVAL
	timer.autostart = true
	timer.timeout.connect(_think)
	add_child(timer)


# Called every THINK_INTERVAL seconds.
func _think():
	if not is_instance_valid(_map_node):
		return
	var grid = _map_node.get_node("Grid")
	if not is_instance_valid(grid):
		return

	if _fill_all_bases():
		return  # Made a build decision; wait for next tick.

	var base_count = _count_bases()
	if base_count < MAX_BASES:
		_try_expand(grid)


# Iterates owned bases and fills each one. Returns true if any structure was placed.
func _fill_all_bases() -> bool:
	for structure in structures:
		if structure.structure_type != "base" or structure.is_under_construction:
			continue
		if _fill_base(structure.current_tile):
			return true
	return false


# Places the next structure for a base: one factory (type balanced globally), then mines.
# Returns true if a structure was placed.
func _fill_base(base_tile: Tile) -> bool:
	var tile: Tile

	# One factory per base; choose whichever type the player has fewer of globally.
	if _count_type_near_base(base_tile, "drone_factory") + _count_type_near_base(base_tile, "tank_factory") == 0:
		var factory_type := _choose_factory_type()
		tile = _find_free_neighbor(base_tile)
		if tile and place_structure(factory_type, tile, _map_node):
			print("AggressiveAI (%s): built %s." % [name, factory_type])
			return true

	# Fill remaining slots with mines.
	tile = _find_free_neighbor(base_tile)
	if tile and place_structure("mine", tile, _map_node):
		print("AggressiveAI (%s): built mine." % name)
		return true

	return false


# Returns the total number of owned (non-under-construction) bases.
func _count_bases() -> int:
	var count: int = 0
	for structure in structures:
		if structure.structure_type == "base" and not structure.is_under_construction:
			count += 1
	return count


# Attempts to place a second base at the best forward site.
func _try_expand(grid) -> void:
	if resources < GameData.STRUCTURE_TYPES["base"]["cost"]:
		return

	var best_tile: Tile = _find_expansion_tile(grid)
	if best_tile:
		if place_structure("base", best_tile, _map_node):
			print("AggressiveAI (%s): expanding — forward base at %s." % [name, best_tile.get_coords()])
	else:
		print("AggressiveAI (%s): no valid expansion site found." % name)


# Scores candidate tiles for a forward base:
#   - Proximity (30%):  close to own territory so supply lines are short.
#   - Aggression (50%): close to the enemy — push the front line forward.
#   - Buildability (20%): enough ring-1 neighbors for mines and factories.
func _find_expansion_tile(grid) -> Tile:
	var forbidden: Dictionary = {}
	var own_base_positions: Array[Vector2] = []

	for structure in structures:
		if structure.structure_type == "base" and not structure.is_under_construction:
			_mark_forbidden_zone(structure.current_tile, FORBIDDEN_RADIUS, forbidden)
			own_base_positions.append(Vector2(structure.current_tile.x, structure.current_tile.z))

	var enemy_centroid: Vector2 = _get_enemy_centroid()

	var best_tile: Tile = null
	var best_score: float = -INF

	for coords in grid.tiles:
		if forbidden.has(coords):
			continue
		var tile: Tile = grid.tiles[coords]
		if not tile.walkable or not tile.buildable or tile.structure != null:
			continue

		var pos := Vector2(tile.x, tile.z)

		# Factor 1 — Proximity: prefer sites close to own territory.
		var nearest_own: float = INF
		for bp in own_base_positions:
			nearest_own = min(nearest_own, pos.distance_to(bp))
		var score_proximity: float = 1.0 - clamp(nearest_own / SCORE_MAX_DIST, 0.0, 1.0)

		# Factor 2 — Aggression: prefer sites close to the enemy.
		var dist_to_enemy: float = pos.distance_to(enemy_centroid)
		var score_aggression: float = 1.0 - clamp(dist_to_enemy / SCORE_MAX_DIST, 0.0, 1.0)

		# Factor 3 — Buildability: count terrain-buildable ring-1 neighbors.
		var buildable_count: int = 0
		for neighbor in tile.neighbors:
			if is_instance_valid(neighbor) and neighbor.buildable:
				buildable_count += 1
		var score_buildable: float = buildable_count / 6.0

		var total: float = SCORE_W_PROXIMITY  * score_proximity  \
				   + SCORE_W_AGGRESSION * score_aggression \
				   + SCORE_W_BUILDABLE  * score_buildable

		if total > best_score:
			best_score = total
			best_tile = tile

	return best_tile
