extends Node3D
class_name Game

const PlayerNode = preload("res://src/Player.gd")
@export var UNIT_MESH_RESOURCE = preload("res://assets/robot_simple.obj")

@onready var map_node = $Map
var players: Array[PlayerNode] = [] # Note: We are storing PlayerNode instances now

# Clears existing players array and initializes players based on config.
# player_configs: Array of Dictionary, e.g., [{id: 0, color: Color.RED, target: Vector2i(5, 5)}]
func initialize_players(player_configs: Array) -> void:
	players.clear()
	
	for config in player_configs:
		var player_node = PlayerNode.new()
		
		# Set Node properties and Data class properties
		player_node.id = config["id"]
		player_node.name = "Player%d" % player_node.id
		player_node.unit_mesh = UNIT_MESH_RESOURCE
		
		player_node.color = config["color"]
		player_node.target = config["target"]
		player_node.flow_field = FlowField.new() # Needs FlowField import
		player_node.units = []
		player_node.resources = 0
		
		# Add Player node to the scene tree
		add_child(player_node)
		players.append(player_node)
		

# Returns a player object based on ID, assuming ID matches index for simplicity.
func get_player(player_id: int): # Removed -> Player type hint as it conflicted with PlayerNode usage
	if player_id >= 0 and player_id < players.size():
		return players[player_id]
	
	push_error("Attempted to access non-existent player with ID: %d" % player_id)
	return null

func _ready() -> void:
	# Hardcoded test data initialization
	initialize_players([
		{"id": 0, "color": Color.RED, "target": Vector2i(5, 5)},
		{"id": 1, "color": Color.BLUE, "target": Vector2i(15, 15)}
	])
	# TEST: Spawn units for player 0 and player 1
	var player0 = get_player(0)
	var player1 = get_player(1)
	
	if player0 and is_instance_valid(map_node):
		player0.spawn_unit(5, 5, map_node)
		player0.units.append(player0.spawn_unit(6, 6, map_node)) # Add to units array as well
	
	if player1 and is_instance_valid(map_node):
		player1.spawn_unit(15, 15, map_node)
		player1.units.append(player1.spawn_unit(16, 16, map_node)) # Add to units array as well
	# Initialize dependent systems that rely on player configuration (e.g., Map flows)
	if is_instance_valid(map_node):
		map_node.initialize_flows()
