# DefensiveAI — Green Team
#
# STRATEGY: Fortify every base with static defenses.
#
# The Defensive AI treats each base as a fortress. It builds a Cannon next to
# every base it owns, making direct assaults costly for the attacker. Units
# produced are used to hold territory rather than push aggressively.
#
# Cannons have short-to-medium range (4 hex) and deal heavy damage (25 per
# hit), so they punish any force that charges straight at a base.
#
# Build order at game start:
#   1. Drone Factory — infantry production
#   2. Cannon         — static defense adjacent to the base
#
# Future expansion behavior (to implement):
#   - Every time a new base is captured or built, immediately place a Cannon
#     next to it before doing anything else.
#   - Place units in a defensive perimeter around owned bases rather than
#     pathing aggressively toward the enemy.
#   - Only build a Tank Factory once all owned bases have a Cannon.
#   - Prioritize repairing damaged structures over building new ones.
#
# Countered by: Long Range AI — artillery outranges the Cannon (8 vs 4 hex)
# and can soften the base from outside cannon range. Players should use
# artillery or flanking infantry to avoid the cannon's kill zone.

class_name DefensiveAI
extends AIPlayer

func start_turn(p_map_node: Node3D):
	print("DefensiveAI (%s): starting turn — defensive build order." % name)

	if structures.size() == 0:
		push_error("DefensiveAI %d: no base structure found." % id)
		return

	var base_tile: Tile = structures[0].current_tile

	# Step 1: Drone Factory for infantry production.
	var factory_tile = _find_free_neighbor(base_tile)
	if factory_tile:
		place_structure("drone_factory", factory_tile, p_map_node)

	# Step 2: Cannon to guard the base.
	var cannon_tile = _find_free_neighbor(base_tile)
	if cannon_tile:
		place_structure("cannon", cannon_tile, p_map_node)


# Returns the first free, walkable neighbor of center_tile, or null.
func _find_free_neighbor(center_tile: Tile) -> Tile:
	for neighbor in center_tile.neighbors:
		if is_instance_valid(neighbor) and neighbor.walkable and neighbor.structure == null:
			return neighbor
	return null
