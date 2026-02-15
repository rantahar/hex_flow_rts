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
const CAMERA_ZOOM_MAX: float = 50.0        # Maximum camera height (most zoomed out)
const CAMERA_ZOOM_START: float = 40.0      # Initial camera height
const CAMERA_RESET_PITCH: float = 55.0     # Degrees — pitch angle used in reset_to()

# --- Raycasting ---

# Length of physics raycasts used for tile selection and hover detection.
const RAYCAST_LENGTH: float = 1000.0
