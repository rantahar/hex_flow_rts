# AggressiveAI — Purple Team
#
# STRATEGY: Early military rush before opponents can establish economy.
#
# The Aggressive AI sacrifices long-term economic growth for immediate combat
# power. It builds both a Drone Factory and a Tank Factory as quickly as
# possible, producing a mixed force of infantry and tanks that attacks before
# opponents have time to build defenses or accumulate resources.
#
# Tanks deal 5× the damage of infantry and absorb punishment — a mixed force
# arriving in the first minutes of the game can crush an unprepared base.
#
# Build order at game start:
#   1. Drone Factory  — cheap infantry flow
#   2. Tank Factory   — heavy hitters for the rush
#   (no mines: the base's own resource generation is enough to sustain two
#    factories in the short window before the game is decided)
#
# Future expansion behavior (to implement):
#   - Set the flow-field target to the nearest enemy base immediately,
#     so all units produced flow directly into the attack.
#   - If the rush is repelled and the game drags on, fall back to building
#     one mine to sustain continued production.
#   - Never build artillery or cannons — all resources go to unit production.
#   - If a base is lost, immediately rush with whatever units remain rather
#     than turtling.
#
# Countered by: Defensive AI — a Cannon next to the enemy base chews through
# the incoming rush. Players should build static defenses early when facing
# Purple, then counter-attack once the rush is spent.

class_name AggressiveAI
extends AIPlayer

func start_turn(p_map_node: Node3D):
	print("AggressiveAI (%s): starting turn — rush build order." % name)

	if structures.size() == 0:
		push_error("AggressiveAI %d: no base structure found." % id)
		return

	var base_tile: Tile = structures[0].current_tile

	# Step 1: Drone Factory — cheap continuous infantry production.
	var factory_tile = _find_free_neighbor(base_tile)
	if factory_tile:
		place_structure("drone_factory", factory_tile, p_map_node)

	# Step 2: Tank Factory — heavy assault units to break defenses.
	# Cost: 400. Together with drone_factory (150) = 550, well within 1000 start budget.
	var tank_tile = _find_free_neighbor(base_tile)
	if tank_tile:
		place_structure("tank_factory", tank_tile, p_map_node)


# Returns the first free, walkable neighbor of center_tile, or null.
func _find_free_neighbor(center_tile: Tile) -> Tile:
	for neighbor in center_tile.neighbors:
		if is_instance_valid(neighbor) and neighbor.walkable and neighbor.structure == null:
			return neighbor
	return null
