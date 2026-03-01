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
