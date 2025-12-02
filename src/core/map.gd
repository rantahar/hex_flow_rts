extends Node3D

# Reference to the root Game node (our parent)
@onready var game_node = get_parent()

@onready var map_generator = $MapGenerator
@onready var grid: Grid = $Grid
var player_flows: Array[FlowField] = []
var player_visualizers: Array[FlowFieldVisualizer] = []
var current_player_id: int = 0
var visualization_timer: Timer

var source_tile: Tile = null
var target_tile: Tile = null

func _ready():
	# 1. Generate the map (which also instantiates tile nodes)
	map_generator.generate_map()
	
	# 2. Register the generated tiles with the Grid
	grid.register_tiles(map_generator.get_tiles())
	
	
# To be called by the Game node after player initialization
func initialize_flows():
	# 1. Initialize flow fields and visualizer
	
	# Ensure capacity for players, size based on initialized players in Game.gd
	player_flows.resize(game_node.players.size())
	player_visualizers.resize(1) # We reuse the single visualizer node $FlowVisualizer
	
	# Store the single visualizer node reference
	var visualizer = $FlowVisualizer
	player_visualizers[0] = visualizer
	
	# Player 0 Setup (using data from initialized player object)
	var player_0_target = game_node.get_player(0).target
	_setup_player_flow(0, player_0_target, visualizer)
	
	# Player 1 Setup (using data from initialized player object)
	var player_1_target = game_node.get_player(1).target
	_setup_player_flow(1, player_1_target, null) # Don't re-setup visualizer, just calculate flow

	# Setup visualization timer (must create the timer node)
	visualization_timer = Timer.new()
	visualization_timer.wait_time = 2.0
	visualization_timer.autostart = true
	visualization_timer.connect("timeout", _on_visualization_timer_timeout)
	add_child(visualization_timer)
	
	# Initial visualization for P0, starting the cycle
	current_player_id = 1 # Start cycle by initializing with P1 flow data
	_on_visualization_timer_timeout() # Run immediately to show P0 first (after cycling from P1)


# Handles tile selection via mouse click (Left click for Source, Right click for Target)
func _unhandled_input(event: InputEvent):
	if event is InputEventMouseButton:
		var tile_under_cursor = _get_tile_under_cursor()
		
		if tile_under_cursor:
			if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
				source_tile = tile_under_cursor
				# Use ClickMarker if it exists to show selection, or just print
				_calculate_flow_field()
			
			elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
				target_tile = tile_under_cursor
				_calculate_flow_field()
				
# Performs a raycast from the camera to find the tile node clicked
func _get_tile_under_cursor() -> Tile:
	var mouse_pos = get_viewport().get_mouse_position()
	
	var camera_node = get_viewport().get_camera_3d()
	if not camera_node:
		return null
		
	var from = camera_node.project_ray_origin(mouse_pos)
	var to = from + camera_node.project_ray_normal(mouse_pos) * 1000.0
	
	var space_state = get_world_3d().direct_space_state
	# IMPORTANT: Raycast only interacts with objects on collision mask layer 1 (default) 
	# or where the tiles are located. Assuming they are on layer 1 by default for StaticBody3D/Colliders.
	var query = PhysicsRayQueryParameters3D.create(from, to, 1) 
	var result = space_state.intersect_ray(query)
	
	if result:
		var collider: Node3D = result.collider
		# Get Tile object from the Grid using the collider node
		var coords = grid.find_tile_by_node(collider)
		if coords != Vector2i(-1, -1):
			return grid.tiles[coords] as Tile
			
	return null

# Helper function to setup flow field for a player ID
func _setup_player_flow(p_id: int, target_coords: Vector2i, visualizer: FlowFieldVisualizer) -> void:
	# Ensure a tile exists at target_coords before proceeding
	if not grid.tiles.has(target_coords):
		print("ERROR: Target tile not found for P%d at %s. Skipping setup." % [p_id, target_coords])
		return

	var target_tile: Tile = grid.tiles[target_coords]
	var targets: Dictionary = {target_tile: 0.0}
	
	# Initialize FlowField instance and calculate flow
	var flow = FlowField.new()
	flow.player_id = p_id
	flow.calculate(targets, grid)
	player_flows[p_id] = flow
	
	if visualizer:
		# Setup the single visualizer node for P0's flow initially.
		# We call visualize_initial_state here to clear/initialize arrows.
		visualizer.setup(flow, grid, p_id)
		visualizer.visualize_initial_state(grid.tiles.values())
	


# Helper function to handle flow field calculation based on user click
func _calculate_flow_field() -> void:
	if source_tile and target_tile:
		# Assume user input sets the target for P0 (ID 0) in interactive mode.
		var p_id = 0
		if p_id >= player_flows.size() or player_flows[p_id] == null:
			print("ERROR: Player 0 flow field not initialized.")
			return
			
		var current_flow = player_flows[p_id]
		var current_visualizer = player_visualizers[0] # Use the single visualizer node
		
		# 1. Update target for current player (P0)
		var targets: Dictionary = {target_tile: 0.0}
		current_flow.calculate(targets, grid)
		
		# 2. Update the visualizer's reference and trigger visualization
		current_visualizer.setup(current_flow, grid, p_id)
		current_visualizer.visualize()
		
		# Note: We are not updating Game.PLAYER_TARGETS here, assuming Game.gd holds fixed initial config.
		# If interactive player target changes need persistence, update Game.PLAYER_TARGETS[p_id].
		

# Cycles visualization between players P0 and P1
func _on_visualization_timer_timeout():
	var next_player_id = (current_player_id + 1) % game_node.players.size()
	current_player_id = next_player_id
	
	if current_player_id >= player_flows.size() or player_flows[current_player_id] == null:
		print("ERROR: Flow field for Player %d is not initialized." % current_player_id)
		return
		
	var current_flow = player_flows[current_player_id]
	var current_visualizer = player_visualizers[0] # The single visualizer instance

	# Update the visualizer's reference to the current player's flow field
	current_visualizer.setup(current_flow, grid, current_player_id)
	current_visualizer.visualize()
	
