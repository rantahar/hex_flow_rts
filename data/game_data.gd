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
		"size": 0.1,
		# Number of formation slots this unit occupies
		"formation_size": 1,
		# Maximum health points
		"max_health": 100.0,
		# Damage dealt per successful attack
		"attack_damage": 10.0,
		# Maximum distance to attack target, measured in hex units
		"attack_range": 1.0,
		# Time in seconds required between attacks
		"attack_cooldown": 1.5,
		# Maximum distance the unit can see, measured in hex units
		"vision_range": 8.0,
		# Resource cost to spawn this unit
		"cost": 100,
		# Tags used for unit classification and logic handling
		"unit_types": ["military", "infantry"]
	},
	
	# Tank: Slow but strong armored unit
	"tank": {
		"display_name": "Tank",
		"mesh_path": "res://assets/units/tank.obj",
		"move_speed": 2.0,
		"size": 0.8,
		# Number of formation slots this unit occupies
		"formation_size": 1,
		"max_health": 500.0,
		"attack_damage": 40.0,
		"attack_range": 4.0,
		"attack_cooldown": 3.0,
		"vision_range": 10.0,
		"cost": 500,
		"unit_types": ["military", "tank"]
	},
	
	# Scout: Fastest unit, used primarily for exploration (no attack capability)
	"scout": {
		"display_name": "Scout",
		"mesh_path": "res://assets/units/scout.obj",
		"move_speed": 8.0,
		"size": 0.4,
		# Number of formation slots this unit occupies
		"formation_size": 1,
		"max_health": 80.0,
		"attack_damage": 0.0,
		"attack_range": 0.0,
		"attack_cooldown": 0.0,
		"vision_range": 12.0,
		"cost": 50,
		"unit_types": ["scout"]
	},
}
const TILES = {
	"grass": {
		"mesh_path": "res://assets/kenney_3d_hex/Models/OBJ format/grass.obj",
		"type_name": "grass",
		"walk_cost": 1.0,
		"walkable": true,
		"weight": 5, # Higher probability
	},
	"dirt": {
		"mesh_path": "res://assets/kenney_3d_hex/Models/OBJ format/dirt.obj",
		"type_name": "dirt",
		"walk_cost": 1.0,
		"walkable": true,
		"weight": 5, # Higher probability
	},
	"mountain": {
		"mesh_path": "res://assets/kenney_3d_hex/Models/OBJ format/grass-hill.obj",
		"type_name": "mountain",
		"walk_cost": 2.0,
		"walkable": true,
		"weight": 1, # Lower probability
	},
	"water": {
		"mesh_path": "res://assets/kenney_3d_hex/Models/OBJ format/water.obj",
		"type_name": "water",
		"walk_cost": 1e20, # Represents infinite cost (Tile.INF)
		"walkable": false,
		"weight": 1, # Lower probability
	},
}

# Defines the delay before game logic starts (e.g., flow field calculation)
const START_DELAY_SECONDS: float = 1.0

# Defines global map dimensions
const MAP_WIDTH: int = 20
const MAP_HEIGHT: int = 20

# Defines configuration data for players
const PLAYER_CONFIGS = [
	{
		"id": 0,
		"display_name": "Red Team",
		"color": Color.RED,
	},
	{
		"id": 1,
		"display_name": "Blue Team",
		"color": Color.BLUE,
	}
]
