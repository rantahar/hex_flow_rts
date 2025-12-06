extends Node3D
class_name Structure

signal unit_produced(unit_type: String, structure: Structure)

const HealthBar3D = preload("res://src/HealthBar3D.gd")
const Grid = preload("res://src/core/Grid.gd")
# We assume the Game script is necessary to interact with Player resources/unit creation
const Game = preload("res://src/Game.gd")
const Player = preload("res://src/Player.gd") # Assuming Player class is defined here
const Tile = preload("res://src/core/Tile.gd") # Assuming Tile class is defined here

var health_bar: HealthBar3D
var config: Dictionary = {}
var grid: Grid = null

var display_name: String = ""
var structure_type: String = "" # e.g., "resource_generator", "unit_producer"
var player_id: int = 0
var size_hex: float = 0.0 # Radius in hex units
var max_health: float = 0.0
var health: float = 0.0
var scale_factor: float = 1.0 # Store scale factor
var current_tile: Tile = null

var mesh_instance: MeshInstance3D

# Resource generation properties (structure_type == "resource_generator")
var resource_generation_rate: float = 0.0
var resource_timer: Timer

# Unit production properties (structure_type == "unit_producer")
var produces_unit_type: String = ""
var production_time: float = 0.0
var production_timer: Timer
var is_producing: bool = false


func _init(structure_config: Dictionary, p_player_id: int, p_current_tile: Tile, world_pos: Vector3):
	"""
	Initializes the structure with configuration, player ID, starting tile, and world position.
	"""
	config = structure_config
	player_id = p_player_id
	current_tile = p_current_tile
	
	# Initialize core stats from config
	size_hex = config.get("size", 0.0)
	max_health = config.get("max_health", 100.0)
	health = max_health
	display_name = config.get("display_name", "Structure")
	structure_type = config.get("structure_type", "")
	
	# Set position to planar world position for now. Height will be corrected after adding to tree.
	position = Vector3(world_pos.x, world_pos.y, world_pos.z)

	# Setup Mesh and Health Bar
	_setup_mesh(config)
	_setup_health_bar()
	
	# Setup specific functionalities
	if structure_type == "resource_generator":
		resource_generation_rate = config.get("resource_generation_rate", 0.0)
		_setup_resource_timer()
	
	if structure_type == "unit_producer":
		produces_unit_type = config.get("produces_unit_type", "")
		production_time = config.get("production_time", 5.0)
		_setup_production_timer()


# --- Initialization Helpers (Identical to Unit.gd mesh/health bar setup) ---

func _setup_mesh(structure_config: Dictionary) -> void:
	"""
	Loads the structure's 3D mesh and applies scaling logic identical to Unit.gd.
	"""
	var mesh_path: String = structure_config.get("mesh_path", "")
	var mesh: Mesh = load(mesh_path)
	if not mesh:
		push_error("Structure %s: Failed to load mesh at path: %s" % [display_name, mesh_path])
		return
	
	# Create mesh instance
	mesh_instance = MeshInstance3D.new()
	mesh_instance.name = "StructureMeshInstance"
	mesh_instance.mesh = mesh
	
	# Calculate target size based on hex unit size (Grid.HEX_SCALE * size_hex)
	var target_unit_world_radius: float = Grid.HEX_SCALE * size_hex
	
	# Calculate the current horizontal size of the mesh (max of X and Z dimensions)
	var aabb_size: Vector3 = mesh.get_aabb().size
	# We want the radius of the mesh for scaling calculation (half of max horizontal size)
	var current_mesh_radius: float = maxf(aabb_size.x, aabb_size.z) / 2.0
	
	# Calculate the required uniform scale factor and store it
	if current_mesh_radius > 0:
		scale_factor = target_unit_world_radius / current_mesh_radius
	else:
		scale_factor = 1.0
		
	mesh_instance.scale = Vector3(scale_factor, scale_factor, scale_factor)
	add_child(mesh_instance)

func _setup_health_bar() -> void:
	"""
	Creates and configures the HealthBar3D node identical to Unit.gd setup.
	"""
	# Health Bar setup
	health_bar = HealthBar3D.new()
	add_child(health_bar)
	
	# Get structure mesh AABB size
	var mesh_aabb_size: Vector3 = mesh_instance.mesh.get_aabb().size
	# Calculate scaled structure size for proportional health bar
	var scaled_unit_size: Vector3 = mesh_aabb_size * scale_factor
	health_bar.setup(scaled_unit_size)
	
	health_bar.update_health(health, max_health)

func _setup_resource_timer():
	"""
	Sets up the timer for periodic resource generation (wait_time 1.0s, autostart true).
	"""
	resource_timer = Timer.new()
	resource_timer.name = "ResourceTimer"
	resource_timer.wait_time = 1.0
	resource_timer.autostart = true
	resource_timer.connect("timeout", _on_resource_timer_timeout)
	add_child(resource_timer)

func _setup_production_timer():
	"""
	Sets up the one-shot timer for unit production.
	"""
	production_timer = Timer.new()
	production_timer.name = "ProductionTimer"
	production_timer.wait_time = production_time
	production_timer.one_shot = true 
	production_timer.connect("timeout", _on_production_timer_timeout)
	add_child(production_timer)

# --- Resource Generation Logic ---

func _on_resource_timer_timeout():
	"""
	Generates resources for the owning player by finding the Game node and Player instance.
	"""
	if resource_generation_rate <= 0:
		return
		
	# Find Game node: Structure -> Map -> Game (assuming standard scene hierarchy)
	var game_node = get_parent().get_parent() 
	
	if is_instance_valid(game_node) and game_node.name == "Game":
		var player: Player = game_node.get_player(player_id)
		if player:
			player.add_resources(resource_generation_rate)
		else:
			push_warning("Resource generator Structure %d: Could not find Player %d." % [get_instance_id(), player_id])

# --- Unit Production Logic ---

func start_production():
	"""
	Sets is_producing to true and starts the production timer.
	"""
	if structure_type != "unit_producer" or is_producing:
		return

	if produces_unit_type.is_empty():
		push_error("Unit Producer %s: produces_unit_type is empty." % display_name)
		return
		
	is_producing = true
	production_timer.start()
	print("Structure %s (Player %d) started producing %s. Time: %f" % [display_name, player_id, produces_unit_type, production_time])

func _on_production_timer_timeout():
	"""
	Callback when a unit is finished producing. Emits signal and restarts production.
	"""
	if not is_producing:
		return
		
	is_producing = false
	emit_signal("unit_produced", produces_unit_type, self)
	
	# Auto-restart timer for continuous production
	start_production()


# --- Health System (Identical to Unit.gd take_damage, adapted death logic) ---

func take_damage(amount: float):
	"""
	Reduces the structure's health and updates the health bar. Destroys the structure on death.
	"""
	health -= amount
	# Clamp current_health to minimum of 0
	health = maxi(0.0, health)
	
	# Call health_bar.update_health
	if is_instance_valid(health_bar):
		health_bar.update_health(health, max_health)
		
	print("Structure %d (Player %d): Took %f damage, remaining health: %f" % [get_instance_id(), player_id, amount, health])
	
	if health <= 0:
		# 1. Get Game node to access Player data
		var game_node = get_parent().get_parent() # Structure -> Map -> Game
		if is_instance_valid(game_node) and game_node.name == "Game":
			var player: Player = game_node.get_player(player_id)
			if player and player.structures.has(self):
				# Remove self from Player.structures array (assuming Player.gd has this array)
				player.structures.erase(self) 
				
		# 2. Release current_tile.structure reference
		if current_tile and current_tile.structure == self:
			current_tile.structure = null
			
		# 3. Remove from scene
		queue_free()

# --- Height Correction (Adapted from Unit.gd) ---

func _ready():
	"""
	Called when the node enters the scene tree for the first time.
	Initializes the Grid reference and corrects the structure's height based on the ground level.
	"""
	var map_node = get_parent()
	# Initialize grid reference (same logic as Unit.gd)
	if map_node and is_instance_valid(map_node.get_node_or_null("Grid")):
		grid = map_node.get_node("Grid")
	
	_correct_height()


func get_structure_height() -> float:
	"""
	Calculates the total height of the structure model in world units (Y dimension).
	"""
	if mesh_instance and mesh_instance.mesh:
		var aabb_size: Vector3 = mesh_instance.mesh.get_aabb().size
		return aabb_size.y * scale_factor
	return 0.0


func _correct_height():
	"""
	Adjusts the structure's Y position to correctly sit on the ground, centered vertically.
	"""
	var map_node = get_parent()
	# Assumes map_node (Map.gd) has get_height_at_world_pos
	var ground_y = map_node.get_height_at_world_pos(position)
	var structure_half_height = get_structure_height() / 2.0
	position.y = ground_y + structure_half_height