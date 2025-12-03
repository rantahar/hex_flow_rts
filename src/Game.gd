extends Node3D
class_name Game
const GameData = preload("res://data/game_data.gd")

@onready var map_node = $Map
var players: Array[Player] = []
var player_visualizers: Array[FlowFieldVisualizer] = []
var current_visualization_player: int = 0
var visualization_timer: Timer

# Clears existing players array and initializes players based on config.
# player_configs: Array of Dictionary, e.g., [{id: 0, color: Color.RED, display_name: "Red Team"}]
func initialize_players(player_configs: Array) -> void:
	players.clear()
	
	for config in player_configs:
		var player_node = Player.new()
		
		# Set Node properties and Data class properties
		player_node.id = config["id"]
		player_node.name = config["display_name"] # Using display_name for Node name
		
		player_node.color = config["color"]
		# player_node.target is set elsewhere, typically by user input.
		player_node.flow_field = FlowField.new() # Needs FlowField import
		player_node.units = []
		player_node.resources = 0
		
		# Add Player node to the scene tree
		add_child(player_node)
		players.append(player_node)
		

# Returns a player object based on ID, assuming ID matches index for simplicity.
func get_player(player_id: int) -> Player:
	if player_id >= 0 and player_id < players.size():
		return players[player_id]
	
	push_error("Attempted to access non-existent player with ID: %d" % player_id)
	return null
func _ready() -> void:
	# Initialize players from centralized data
	initialize_players(GameData.PLAYER_CONFIGS)
	
	# Set player targets (currently hardcoded as they were not moved to GameData)
	var player0 = get_player(0)
	var player1 = get_player(1)

	# Set targets (using original hardcoded targets)
	if player0:
		player0.target = Vector2i(5, 5)
	if player1:
		player1.target = Vector2i(15, 15)
		
	# TEST: Spawn units for player 0 and player 1
	# Spawn a cluster of units around the starting position (e.g., at 1,1) for player 0
	if player0 and is_instance_valid(map_node):
		for x_offset in range(3):
			for z_offset in range(3):
				var spawn_x = 1 + x_offset
				var spawn_z = 1 + z_offset
				var unit = player0.spawn_unit(spawn_x, spawn_z, map_node, "infantry")
				if unit:
					player0.units.append(unit)
		
	# Spawn a cluster of units around the starting position (e.g., at 20,20) for player 1
	if player1 and is_instance_valid(map_node):
		for x_offset in range(3):
			for z_offset in range(3):
				var spawn_x = 20 + x_offset
				var spawn_z = 20 + z_offset
				var unit = player1.spawn_unit(spawn_x, spawn_z, map_node, "infantry")
				if unit:
					player1.units.append(unit)
			
	# Wait for specified delay before calculating flow fields
	await get_tree().create_timer(GameData.START_DELAY_SECONDS).timeout
	
	_post_ready_setup()

# Initializes flow fields and visualization after a delay
func _post_ready_setup() -> void:
	# Initialize flow fields
	player_visualizers.resize(1)
	
	var visualizer = map_node.get_node("FlowVisualizer")
	player_visualizers[0] = visualizer
	var grid = map_node.get_node("Grid")
	
	# Calculate flow fields for all players
	players[0].calculate_flow(grid) # Calculate P0 flow (will be visualized immediately)
	players[1].calculate_flow(grid) # Calculate P1 flow
	
	# Setup visualization timer
	visualization_timer = Timer.new()
	visualization_timer.wait_time = 2.0
	visualization_timer.autostart = true
	visualization_timer.connect("timeout", _on_visualization_timer_timeout)
	add_child(visualization_timer)
	
	current_visualization_player = 1
	_on_visualization_timer_timeout()

# Cycles visualization between players P0 and P1
func _on_visualization_timer_timeout():
	var next_player_id = (current_visualization_player + 1) % players.size()
	current_visualization_player = next_player_id
	
	if current_visualization_player >= players.size():
		push_error("Game: Invalid player index %d" % current_visualization_player)
		return
		
	var current_player: Player = players[current_visualization_player]
	
	# Validation: check player exists
	if not current_player:
		push_error("Game: Player %d is null." % current_visualization_player)
		return
		
	# Validation: check player.flow_field not null
	var current_flow = current_player.flow_field
	if not current_flow:
		push_error("Game: Flow field for Player %d is not initialized" % current_visualization_player)
		return
	
	# Check if a visualizer is registered. We currently only support one visualizer.
	if player_visualizers.is_empty() or player_visualizers[0] == null:
		return
		
	var current_visualizer = player_visualizers[0]
	var grid = map_node.get_node("Grid") # Need grid reference here
	
	# Update the visualizer's reference to the current player's flow field
	current_visualizer.update_visualization(current_flow, grid, current_visualization_player)
