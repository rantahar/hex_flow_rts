# Global Gameplay Configuration Constants
# Centralizes values used across different scripts for easier balancing and tuning.

extends Resource

# --- FlowField Constants ---

# Multiplier applied to tile density (number of units occupying the tile)
# when calculating the movement cost in the flow field. Higher value means
# units prioritize moving through less dense areas.
const DENSITY_COST_MULTIPLIER = 5

# Cost multiplier applied to a flow field tile when it is blocked by a
# friendly formation.
const FULL_FORMATION_MULTIPLIER = 100

# --- Game Timer Constants ---

# Time interval (in seconds) between recalculations of the flow field.
# Controls how frequently pathfinding updates occur.
const FLOW_RECALC_INTERVAL = 2.0

# --- Player/Unit Spawning Constants ---

# Time interval (in seconds) between spawning new units for the player.
const SPAWN_INTERVAL = 1.0