extends Node3D
class_name Game
const GameData = preload("res://data/game_data.gd")
const GameConfig = preload("res://data/game_config.gd")
const ResourceDisplay = preload("res://src/ResourceDisplay.gd")
const BuildMenu = preload("res://src/BuildMenu.gd")
# Placeholder constant until StructurePlacer.gd is created
const StructurePlacer = preload("res://src/StructurePlacer.gd")
const AIPlayer = preload("res://src/AIPlayer.gd")

@onready var map_node = $Map
@onready var canvas_layer = $CanvasLayer
@onready var structure_placer: StructurePlacer = $StructurePlacer

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
		var player_node
		
		var player_type = config.get("type", "human") # Default to human
		
		if player_type == "human":
			player_node = Player.new(config["id"], config)
		elif player_type == "ai":
			player_node = AIPlayer.new(config["id"], config)
		else:
			push_error("Unknown player type '%s' found in config for Player ID %d." % [player_type, config["id"]])
			continue
		
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
	
	# Determine the human player dynamically based on config
	var human_player: Player = null
	for p in players:
		if is_instance_valid(p) and p.config.get("type") == "human":
			human_player = p
			break
	
	if human_player == null:
		push_warning("No human player found in configuration.")

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

		# 2. Call AI start turn logic if applicable
		if player.config.get("type") == "ai":
			# Ensure we only call this on AI players
			if player is AIPlayer:
				player.start_turn(map_node)
			else:
				push_error("Player ID %d configured as 'ai' but is not an AIPlayer instance." % player.id)

	# Set the human player reference on the StructurePlacer instance
	if is_instance_valid(structure_placer) and is_instance_valid(human_player):
		structure_placer.set_human_player(human_player)
		
	# UI Setup for the human player
	if is_instance_valid(human_player) and is_instance_valid(canvas_layer):
		# Paths assume CanvasLayer is a direct child of Game, and MarginContainer is a direct child of CanvasLayer.
		# Assumes the first MarginContainer holds ResourceDisplay and the second holds BuildMenu.
		var resource_display = canvas_layer.get_node("MarginContainer/ResourceDisplay")
		var build_menu = canvas_layer.get_node("MarginContainer2/BuildMenu")
		
		if not is_instance_valid(build_menu):
			push_error("Game: Could not find BuildMenu node at path MarginContainer2/BuildMenu. Check game.tscn.")
		
		if is_instance_valid(resource_display) and resource_display is ResourceDisplay:
			resource_display.setup(human_player)
		if is_instance_valid(build_menu) and build_menu is BuildMenu:
			build_menu.setup(human_player)
			
			# --- Building UI Signal Handling ---
			# Connect the BuildMenu's selected signal to the placement handler
			if build_menu.has_signal("structure_selected"):
				build_menu.structure_selected.connect(_on_structure_selected)
				
	# Connect hex click signal from camera for placement confirmation
	if $Camera3D.has_signal("hex_clicked"):
		$Camera3D.hex_clicked.connect(_on_hex_clicked)

	# Wait for specified delay before starting visualization setup
	await get_tree().create_timer(GameData.START_DELAY_SECONDS).timeout
	
	_post_ready_setup()

# --- Placement Mode Handling ---

func _on_structure_selected(structure_type: String):
	"""
	Initiates structure placement mode for the human player.
	"""

	if is_instance_valid(structure_placer):
		structure_placer.enter_placement_mode(structure_type)
		print("Game: Entered placement mode for %s." % structure_type)
	else:
		push_error("Game._on_structure_selected: StructurePlacer node is not set up.")

func _on_hex_clicked(tile: Tile):
	"""
	Handles a click on a hexagonal tile, primarily for structure placement confirmation.
	"""
	if is_instance_valid(structure_placer) and structure_placer.is_active():
		# structure_placer.attempt_placement handles resource checks and calling player.place_structure
		var success = structure_placer.attempt_placement(tile, map_node)
		
		if success:
			print("Game: Structure placed successfully at %s." % tile.get_coords())
		
		# Always consume the click event if placement mode is active
		return
	# If placement mode is inactive, the RTSCamera handles the click as normal unit movement/selection.
	pass


# Adds the raycast logic for mouse hover detection (Task 2 refactoring)
func _get_hovered_tile() -> Tile:
	var viewport = get_viewport()
	var camera = $Camera3D
	var grid = map_node.get_node_or_null("Grid")
	
	if not is_instance_valid(camera) or not is_instance_valid(grid):
		return null
	
	var space_state = get_world_3d().direct_space_state
	var mouse_pos = viewport.get_mouse_position()
	var ray_origin = camera.project_ray_origin(mouse_pos)
	var ray_end = camera.project_ray_normal(mouse_pos) * 1000.0 + ray_origin
	
	var query = PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
	var intersection = space_state.intersect_ray(query)
	
	if intersection:
		var collider = intersection.collider
		var tile_coords: Vector2i = Vector2i(-1, -1)
		
		# Traverse up the tree until a registered StaticBody3D tile node is found.
		# This replicates the robust clicking logic from RTSCamera.gd.
		var current_node: Node = collider
		var tile_node: StaticBody3D = null
		
		while current_node:
			# NOTE: Assuming tiles are StaticBody3D and registered in Grid
			if current_node is StaticBody3D:
				tile_coords = grid.find_tile_by_node(current_node)
				if tile_coords != Vector2i(-1, -1):
					tile_node = current_node
					break
			
			# Optimization: Stop searching if we hit the top-level map node
			if current_node == map_node:
				break
				
			current_node = current_node.get_parent()
		
		if tile_coords != Vector2i(-1, -1):
			# Look up Tile object
			return grid.tiles.get(tile_coords)
	
	return null

# Handles placement preview updates and cancellation
func _process(delta: float) -> void:
	if is_instance_valid(structure_placer) and structure_placer.is_active():
		# Handle cancellation:
		if Input.is_action_just_pressed("ui_cancel"):
			structure_placer.exit_placement_mode()
			print("Game: Placement mode cancelled.")
			return

		# Handle placement preview updates:
		var hovered_tile = _get_hovered_tile()
		
		# Only update preview if placement mode is active for a valid player
		if is_instance_valid(hovered_tile):
			structure_placer.update_preview(hovered_tile)


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
