extends Node3D
class_name Game
const GameData = preload("res://data/game_data.gd")
const GameConfig = preload("res://data/game_config.gd")

@onready var map_node = $Map
var players: Array[Player] = []
var player_visualizers: Array[FlowFieldVisualizer] = []
var current_visualization_player: int = 0
var visualization_timer: Timer
var flow_recalculation_timer: Timer
var game_time_seconds: int = 0
var game_clock_timer: Timer

# Clears existing players array and initializes players based on config.
# player_configs: Array of Dictionary, e.g., [{id: 0, color: Color.RED, display_name: "Red Team"}]
func initialize_players(player_configs: Array) -> void:
	"""
	Clears existing players and initializes new Player instances based on the provided configurations.
	Sets up flow fields and adds player nodes to the scene tree.

	Arguments:
	- player_configs (Array): Array of player configuration dictionaries.
	"""
	players.clear()
	
	for config in player_configs:
		var player_node = Player.new(config["id"], config)
		
		# Set Node properties and Data class properties
		player_node.id = config["id"]
		player_node.name = config["display_name"] # Using display_name for Node name
		
		player_node.color = config["color"]
		# player_node.target is set elsewhere, typically by user input.
		player_node.flow_field = FlowField.new()
		player_node.flow_field.player_id = player_node.id
		# player_node.units and player_node.resources are initialized in Player.gd
		
		# Add Player node to the scene tree
		add_child(player_node)
		players.append(player_node)
		

# Returns a player object based on ID, assuming ID matches index for simplicity.
func get_player(player_id: int) -> Player:
	"""
	Retrieves a player object by their ID.

	Arguments:
	- player_id (int): The ID of the player to retrieve.

	Returns:
	- Player: The Player instance corresponding to the ID, or null if not found.
	"""
	if player_id >= 0 and player_id < players.size():
		return players[player_id]
	
	push_error("Attempted to access non-existent player with ID: %d" % player_id)
	return null

# Helper function to ensure a spawn tile is walkable, attempting to find a nearby tile if not.
func _find_walkable_spawn_tile(grid: Grid, preferred_coords: Vector2i) -> Tile:
	"""
	Helper function to find a walkable spawn tile, starting at a preferred coordinate.
	If the preferred tile is unwalkable, searches immediately adjacent neighbor tiles.

	Arguments:
	- grid (Grid): The grid instance containing all tiles.
	- preferred_coords (Vector2i): The desired grid coordinates for the spawn tile.

	Returns:
	- Tile: A walkable Tile object, or null if no walkable tile is found nearby.
	"""
	var tile = grid.tiles.get(preferred_coords)
	if tile and tile.walkable:
		return tile

	# If the preferred tile is not walkable or doesn't exist, search nearby neighbors (1-ring distance)
	push_warning("Preferred spawn tile (%s) is not walkable. Searching neighbors..." % preferred_coords)

	# We need Tile coordinates and neighbor data to properly check neighbors.
	# We will retrieve the Tile object first, if it exists.
	if tile:
		for neighbor_tile in tile.neighbors:
			if neighbor_tile.walkable:
				push_warning("Found walkable spawn tile at (%s)." % neighbor_tile.get_coords())
				return neighbor_tile
	
	push_error("Could not find a walkable spawn tile near %s." % preferred_coords)
	return null

# Helper function to find the first walkable, un-occupied neighbor tile.
func _find_free_neighbor_tile(grid: Grid, center_tile: Tile) -> Tile:
	"""
	Searches immediately adjacent neighbor tiles for one that is walkable and
	not occupied by a structure.

	Arguments:
	- grid (Grid): The grid instance. (Currently unused but kept for consistency)
	- center_tile (Tile): The tile whose neighbors are checked.

	Returns:
	- Tile: A free, walkable neighbor tile, or null.
	"""
	if not center_tile:
		return null
		
	for neighbor_tile in center_tile.neighbors:
		# Check if tile is walkable and free of structures
		if neighbor_tile.walkable and neighbor_tile.structure == null:
			return neighbor_tile
			
	return null

func _ready() -> void:
	"""
	Called when the node enters the scene tree for the first time.
	Initializes players, sets targets and spawn points, calculates initial flow fields,
	and initiates the post-ready setup after a brief delay.
	"""
	# Initialize players from centralized data
	initialize_players(GameData.PLAYER_CONFIGS)
	
	# Set player targets (currently hardcoded as they were not moved to GameData)
	var player0 = get_player(0)
	var player1 = get_player(1)

	var grid = map_node.get_node("Grid")
	
	# Coordinates for testing spawning and targeting (20x20 map)
	const P0_TARGET_COORDS = Vector2i(15, 15)
	const P1_TARGET_COORDS = Vector2i(5, 5)
	const P0_SPAWN_COORDS = Vector2i(5, 5)
	const P1_SPAWN_COORDS = Vector2i(15, 15)

	# Set player targets and spawn tiles
	if player0 and grid:
		player0.target = P0_TARGET_COORDS
		player0.spawn_tile = _find_walkable_spawn_tile(grid, P0_SPAWN_COORDS)
		if player0.spawn_tile:
			player0.calculate_flow(grid) # Trigger P0 flow calculation
		
	if player1 and grid:
		player1.target = P1_TARGET_COORDS
		player1.spawn_tile = _find_walkable_spawn_tile(grid, P1_SPAWN_COORDS)
		if player1.spawn_tile:
			player1.calculate_flow(grid) # Trigger P1 flow calculation
	
	# Task 5: Spawn initial bases for each player
	for player in players:
		if not is_instance_valid(player) or not player.spawn_tile:
			continue
			
		# 1. Place the Main Base (cost 0, not buildable by normal means)
		var success = player.place_structure("base", player.spawn_tile, map_node)
		if not success:
			push_error("Failed to place base for Player %d at %s." % [player.id, player.spawn_tile.get_coords()])
			continue

		# 2. For testing, place a Drone Factory next to the base (cost 200, buildable)
		var factory_tile = _find_free_neighbor_tile(grid, player.spawn_tile)
		if is_instance_valid(factory_tile):
			# Note: Drone factory costs 200 resources, but the player starts with 1000.
			var factory_success = player.place_structure("drone_factory", factory_tile, map_node)
			if not factory_success:
				push_error("Failed to place drone_factory for Player %d next to base at %s." % [player.id, factory_tile.get_coords()])
		else:
			push_error("Could not find a free tile next to the base for Player %d to place drone_factory." % player.id)

	# NOTE: Manual unit spawns removed as per task requirement.
			
	# Wait for specified delay before starting visualization setup
	await get_tree().create_timer(GameData.START_DELAY_SECONDS).timeout
	
	_post_ready_setup()

# Initializes flow fields and visualization after a delay
func _post_ready_setup() -> void:
	"""
	Initializes periodic timers for flow field recalculation, visualization cycling, and game clock.
	Called after the map and players are fully set up.
	"""
	# Initialize flow fields
	player_visualizers.resize(1)
	
	var visualizer = map_node.get_node("FlowVisualizer")
	player_visualizers[0] = visualizer
	
	# Setup flow recalculation timer (needed for dynamic flow costs like unit density)
	flow_recalculation_timer = Timer.new()
	flow_recalculation_timer.wait_time = GameConfig.FLOW_RECALC_INTERVAL
	flow_recalculation_timer.autostart = true
	flow_recalculation_timer.timeout.connect(_on_flow_recalculation_timer_timeout)
	add_child(flow_recalculation_timer)
	
	# Setup visualization timer
	visualization_timer = Timer.new()
	visualization_timer.wait_time = 2.0
	visualization_timer.autostart = true
	visualization_timer.timeout.connect(_on_visualization_timer_timeout)
	add_child(visualization_timer)

	# Setup game clock timer (1 second interval)
	game_clock_timer = Timer.new()
	game_clock_timer.wait_time = 1.0
	game_clock_timer.autostart = true
	game_clock_timer.timeout.connect(_on_game_clock_timer_timeout)
	add_child(game_clock_timer)
	
	current_visualization_player = 1
	_on_visualization_timer_timeout()

# Cycles visualization between players P0 and P1
func _on_visualization_timer_timeout():
	"""
	Timer callback to cycle the flow field visualization between different players.
	Updates the FlowFieldVisualizer node to display the current player's flow field.
	"""
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


# Recalculates flow fields for all players periodically
func _on_flow_recalculation_timer_timeout():
	"""
	Timer callback to periodically trigger flow field recalculation for all active players.
	This is important for handling dynamic map costs (e.g., changing unit density).
	"""
	var grid = map_node.get_node("Grid")
	if not grid:
		push_error("Game: Grid node missing during flow recalculation.")
		return
		
	for player in players:
		if is_instance_valid(player):
			player.calculate_flow(grid)

# Called every second to update game time and print status
func _on_game_clock_timer_timeout() -> void:
	"""
	Timer callback executed every second to update the in-game clock and display
	the current game time and total unit count.
	"""
	game_time_seconds += 1
	var minutes = floor(game_time_seconds / 60)
	var seconds = game_time_seconds % 60
	var game_clock_string = "%02d:%02d" % [minutes, seconds]

	var total_units: int = 0
	for player in players:
		if is_instance_valid(player):
			total_units += player.units.size()

	print("Game Clock: %s | Total Units: %d" % [game_clock_string, total_units])
