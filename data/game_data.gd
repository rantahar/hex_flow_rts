# Defines configuration data for all available unit types in the game.
# This script is intended to be loaded as a singleton or accessed statically for global game data.

const UNIT_TYPES = {
	# Infantry: Fast and weak basic unit
	"infantry": {
		# User-friendly name for display
		"display_name": "Infantry",
		# Path to the unit's 3D mesh file (.obj, .glb, etc.)
		"mesh_path": "res://assets/robot_simple.obj",
		# Movement speed in units per second
		"move_speed": 0.5,
		# Radius for collision and selection, measured in hex units
		"size": 0.08,
		# Number of formation slots this unit occupies
		"formation_size": 1,
		# Maximum health points
		"max_health": 100.0,
		# Damage dealt per successful attack
		"attack_damage": 1.0,
		# Maximum distance to attack target, measured in hex units
		"attack_range": 1.0,
		# Time in seconds required between attacks
		"attack_cooldown": 2,
		# Maximum distance the unit can see, measured in hex units
		"vision_range": 8.0,
		# Resource cost to spawn this unit
		"cost": 50,
		# Tags used for unit classification and logic handling
		"unit_types": ["military", "infantry"]
	},
	
	# Tank: Slow unit with range
	"tank": {
		"display_name": "Tank",
		"mesh_path": "res://assets/robot_simple.obj",
		"move_speed": 0.2,
		"size": 0.16,
		"formation_size": 2,
		"max_health": 200.0,
		"attack_damage": 5.0,
		"attack_range": 2.0,
		"attack_cooldown": 5.0,
		"vision_range": 10.0,
		"cost": 150,
		"unit_types": ["military", "tank"]
	},
}

const STRUCTURE_TYPES = {
	"base": {
		"display_name": "Base",
		"mesh_path": "res://assets/base.obj",
		"size": 0.3,
		"cost": 500,
		"buildable": true,
		"max_health": 200,
		"resource_generation_rate": 10,
		"self_repair_rate": 1,
		"min_spacing": 5,
		"category": "base",
		"y_offset_fraction": 0.0
	},
	
	"drone_factory": {
		"display_name": "Drone Factory",
		"mesh_path": "res://assets/factory.obj",
		"size": 0.2,
		"buildable": true,
		"cost": 150,
		"max_health": 50,
		"produces_unit_type": "infantry",
		"production_time": 5.0,
		"production_rate_max": 1.0,
		"category": "improvement",
		"y_offset_fraction": 0.0
	},

	"tank_factory": {
		"display_name": "Tank Factory",
		"mesh_path": "res://assets/factory.obj",
		"size": 0.3,
		"buildable": true,
		"cost": 400,
		"max_health": 100,
		"produces_unit_type": "tank",
		"production_time": 10.0,
		"production_rate_max": 1.0,
		"category": "improvement",
		"y_offset_fraction": 0.0
	},
	
	"mine": {
		"display_name": "Mine",
		"mesh_path": "res://assets/mine.obj",
		"drill_hole": true,
		"size": 0.25,
		"cost": 100,
		"max_health": 25,
		"resource_generation_rate": 5,
		"category": "improvement",
		"y_offset_fraction": -0.8 # Sink the mine halfway into the tile
	},
	
	"cannon": {
		"display_name": "Cannon",
		"mesh_path": "res://assets/robot_simple.obj",
		"size": 0.25,
		"cost": 300,
		"max_health": 100,
		"attack_damage": 120,
		"attack_range": 4,
		"attack_cooldown": 1.0,
		"category": "improvement",
		"y_offset_fraction": 0.0
	},
	
	"artillery": {
		"display_name": "Artillery",
		"mesh_path": "res://assets/robot_simple.obj",
		"size": 0.3,
		"cost": 200,
		"max_health": 25,
		"attack_damage": 60,
		"attack_range": 8,
		"attack_cooldown": 3.0,
		"aoe_radius": 1,
		"category": "forward",
		"y_offset_fraction": 0.0
	},
}

const BUILDER_CONFIG = {
	"max_carry": 20,
	"mesh_path": "res://assets/robot.obj",
	"size": 0.05,
	"move_speed": 0.5,
	"max_health": 20.0,
	"spawn_interval": 0.5,
	"stuck_timeout": 1.0,  # seconds before a stuck builder gives up and refunds resources
}

const ROAD_CONFIG = {
	"cost_per_segment": 10,
	"water_cost_multiplier": 3.0,
	"road_tile_cost": 0.3,
	"display_name": "Road",
	"max_hp": 50.0,
	"line_width": 0.06,
	"line_height": 0.03,
	"visual_y_offset": 0.08,
}

const TILES = {
	"grass": {
		"mesh_path": "res://assets/kenney_3d_hex/Models/OBJ format/grass.obj",
		"type_name": "grass",
		"walk_cost": 1.0,
		"walkable": true,
		"weight": 20, # Higher probability
		"buildable": true,
	},
	"dirt": {
		"mesh_path": "res://assets/kenney_3d_hex/Models/OBJ format/dirt.obj",
		"type_name": "dirt",
		"walk_cost": 1.0,
		"walkable": true,
		"weight": 20, # Higher probability
		"buildable": true,
	},
	"mountain": {
		"mesh_path": "res://assets/kenney_3d_hex/Models/OBJ format/grasshill.obj",
		"type_name": "mountain",
		"walk_cost": 2.0,
		"walkable": true,
		"weight": 1, # Lower probability
		"buildable": false,
	},
	"water": {
		"mesh_path": "res://assets/kenney_3d_hex/Models/OBJ format/water.obj",
		"type_name": "water",
		"walk_cost": 1e20, # Represents infinite cost (Tile.INF)
		"walkable": false,
		"weight": 1, # Lower probability
		"buildable": false,
	},
}

# Defines the delay before game logic starts (e.g., flow field calculation)
const START_DELAY_SECONDS: float = 1.0

# How often (seconds) each resource-generating structure ticks
const RESOURCE_TICK_INTERVAL: float = 1.0

# Retry delay (seconds) when a factory cannot afford its next unit
const PRODUCTION_RETRY_INTERVAL: float = 1.0

# Number of infantry each player's base spawns automatically at game start
const INITIAL_RESERVE_SIZE: int = 20
# Rate at which the initial reserve is spawned (units per second)
const INITIAL_RESERVE_RATE: float = 1.0

# Defines global map dimensions
const MAP_WIDTH: int = 20
const MAP_HEIGHT: int = 20

# Defines configuration data for players
const PLAYER_TEMPLATES = [
	{"display_name": "Red Team",    "color": Color.RED,                  "type": "human"},
	{"display_name": "Blue Team",   "color": Color.BLUE,                 "type": "ai", "ai_type": "greedy"},
	{"display_name": "Green Team",  "color": Color.GREEN,                "type": "ai", "ai_type": "defensive"},
	{"display_name": "Yellow Team", "color": Color.YELLOW,               "type": "ai", "ai_type": "long_range"},
	{"display_name": "Purple Team", "color": Color(0.5, 0.0, 0.5, 1.0),  "type": "ai", "ai_type": "aggressive"},
	{"display_name": "Orange Team", "color": Color.ORANGE,               "type": "ai", "ai_type": "greedy"},
]

static func make_player_configs(num: int) -> Array:
	var configs: Array = []
	for i in range(num):
		var t: Dictionary = PLAYER_TEMPLATES[i].duplicate()
		t["id"] = i
		t["starting_resources"] = 1000.0
		configs.append(t)
	return configs

# Default to 2 players for the start-menu demo; overwritten by _on_new_game_pressed before each game.
static var PLAYER_CONFIGS: Array = [
	{"id": 0, "display_name": "Red Team",  "color": Color.RED,  "starting_resources": 1000.0, "type": "human"},
	{"id": 1, "display_name": "Blue Team", "color": Color.BLUE, "starting_resources": 1000.0, "type": "ai", "ai_type": "greedy"},
]
