# LongRangeAI — Yellow Team
#
# STRATEGY: Area denial through artillery positioned behind the front line.
#
# Artillery has the longest attack range in the game (8 hex, AoE radius 1)
# and deals massive damage (40 per shot). The Long Range AI exploits this by
# placing artillery further back from the combat line, where enemy units cannot
# easily reach it while it bombards formations approaching the front.
#
# This makes Yellow hard to push into — infantry gets shredded before it
# closes to melee range, and even tanks take heavy attrition.
#
# Build order at game start:
#   1. Drone Factory — needed for infantry
#   2. Artillery      — placed adjacent to the base for now; future logic
#                       will walk it back 2-3 tiles behind the front line
#
# Future expansion behavior (to implement):
#   - Detect the approximate "front line" (median tile between own and enemy
#     bases) and place artillery 3–4 tiles behind it.
#   - Build multiple artillery batteries as income grows.
#   - Use infantry from the Drone Factory to screen the artillery from flankers.
#   - Avoid building cannons — artillery at range makes them redundant.
#
# Countered by: Aggressive AI — a fast rush can close the distance before
# artillery fire is decisive. Players should flank around the kill zone
# or commit massed infantry to overwhelm the screen units quickly.

class_name LongRangeAI
extends AIPlayer

func start_turn(p_map_node: Node3D):
	print("LongRangeAI (%s): starting turn — artillery build order." % name)

	if structures.size() == 0:
		push_error("LongRangeAI %d: no base structure found." % id)
		return

	var base_tile: Tile = structures[0].current_tile

	# Step 1: Drone Factory for infantry screening units.
	var factory_tile = _find_free_neighbor(base_tile)
	if factory_tile:
		place_structure("drone_factory", factory_tile, p_map_node)

	# Step 2: Artillery for long-range bombardment.
	# TODO: In future, walk back from the flow-field front line to find a tile
	# 3-4 hexes behind the median combat boundary instead of using a base neighbor.
	var arty_tile = _find_free_neighbor(base_tile)
	if arty_tile:
		place_structure("artillery", arty_tile, p_map_node)


# Returns the first free, walkable neighbor of center_tile, or null.
func _find_free_neighbor(center_tile: Tile) -> Tile:
	for neighbor in center_tile.neighbors:
		if is_instance_valid(neighbor) and neighbor.walkable and neighbor.structure == null:
			return neighbor
	return null
