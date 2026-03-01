# Global Gameplay Configuration Constants
# Centralizes values used across different scripts for easier balancing and tuning.

# --- World Scale ---

# Hex grid scale factor: world-units per hex-unit radius
const HEX_SCALE: float = 0.6

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

# Interval (in seconds) at which the game clock ticks.
const GAME_CLOCK_INTERVAL: float = 1.0

# How often (in seconds) the flow field visualizer cycles between players.
const VISUALIZER_CYCLE_INTERVAL: float = 2.0

# --- Unit / Builder Polling Intervals ---

# How often (in seconds) an idle military unit checks whether to move.
const UNIT_MOVEMENT_CHECK_INTERVAL: float = 0.5

# How often (in seconds) an idle builder checks whether to move.
const BUILDER_MOVEMENT_CHECK_INTERVAL: float = 0.5

# How often (in seconds) a unit or structure checks for attack opportunities.
const ATTACK_CHECK_INTERVAL: float = 0.25

# --- Visual Effects ---

# Duration (in seconds) the muzzle flash light stays on after each attack.
const MUZZLE_FLASH_DURATION: float = 0.15

# OmniLight3D range for the muzzle flash effect.
const MUZZLE_FLASH_RANGE: float = 0.5

# Color of the muzzle flash light.
const MUZZLE_FLASH_COLOR = Color(1.0, 0.7, 0.3)

# --- Camera Constants ---

const CAMERA_STEP_SIZE: float = 0.05       # Pan speed coefficient
const CAMERA_EDGE_THRESHOLD: float = 20.0  # Pixels from edge that trigger edge-scroll
const CAMERA_ZOOM_SPEED: float = 0.5       # Zoom speed per scroll tick
const CAMERA_ZOOM_MIN: float = 1.0         # Minimum camera height (most zoomed in)
const CAMERA_ZOOM_MAX: float = 30.0        # Maximum camera height (most zoomed out)
const CAMERA_ZOOM_START: float = 2.0      # Initial camera height
const CAMERA_ZOOM_STRATEGIC: float = 5.0  # Height threshold for strategic view
const CAMERA_RESET_PITCH: float = 55.0     # Degrees — pitch angle used in reset_to()

# --- Raycasting ---

# Length of physics raycasts used for tile selection and hover detection.
const RAYCAST_LENGTH: float = 1000.0

# --- Map Generation ---

# Minimum hex distance required between any two player spawn points.
const MAP_SPAWN_MIN_DISTANCE: int = 10

# Number of border tiles used for the "coast" map type water edge.
const MAP_COAST_EDGE_WIDTH: int = 2

# Hex radius of the central lake in the "lake" map type.
const MAP_LAKE_RADIUS: int = 3

# Shortest and longest possible mountain range (in tiles).
const MAP_MOUNTAIN_MIN_LENGTH: int = 6
const MAP_MOUNTAIN_MAX_LENGTH: int = 10

# Probability (0–1) that a mountain range step deviates one direction.
const MAP_MOUNTAIN_DEVIATION_CHANCE: float = 0.3

# How many times each adjacent tile type is added to the weighted pool
# when filling unassigned tiles (higher = stronger terrain clustering).
const MAP_NEIGHBOR_INFLUENCE_WEIGHT: int = 10
