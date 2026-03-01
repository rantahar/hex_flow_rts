extends Node3D
class_name Structure

signal unit_produced(unit_type: String, structure: Structure)
signal destroyed(structure: Structure)

const HealthBar3D = preload("res://src/HealthBar3D.gd")

var health_bar: HealthBar3D
var config: Dictionary = {}
var grid: Grid = null

var display_name: String = ""
var structure_type: String = "" # e.g., "base", "mine", "drone_factory"
var player_id: int = 0
var size_hex: float = 0.0 # Radius in hex units
var max_health: float = 0.0
var health: float = 0.0
var scale_factor: float = 1.0 # Store scale factor
var current_tile: Tile = null

var mesh_instance: MeshInstance3D

# Resource generation properties
var resource_generation_rate: float = 0.0
var resource_timer: Timer

# Unit production properties
var produces_unit_type: String = ""
var production_time: float = 0.0
var production_timer: Timer
var is_producing: bool = false
var is_waiting_for_resources: bool = false

# Production control toggles
var resource_generation_enabled: bool = true
var unit_production_enabled: bool = true

# Attack properties
var attack_damage: float = 0.0
var attack_range_hex: float = 0.0
var attack_cooldown: float = 0.0
var last_attack_time: float = 0.0
var attack_check_timer: Timer
var muzzle_flash: OmniLight3D
var muzzle_flash_timer: Timer

# Construction state
var is_under_construction: bool = false
var construction_cost: float = 0.0  # Total resource cost, needed for HP contribution calc
var resources_pending: float = 0.0  # Resources still to dispatch via builders
var resources_in_transit: float = 0.0  # Resources currently being carried by builders already sent
var ghost_material: Material = null

# Base builder queue (only used by base-category structures)
var construction_queue: Array = []  # Entries: { "target": Node, "type": "structure"|"road" }
var builder_spawn_timer: Timer = null
var queue_index: int = 0

# Selection state for UI interaction
var is_selected: bool = false

# Material management for selection feedback
var original_material: Material = null
var selected_material: Material = null

func _init(structure_config: Dictionary, p_structure_type: String, p_player_id: int, p_current_tile: Tile, world_pos: Vector3, p_under_construction: bool = false):
	"""
	Initializes the structure with configuration, player ID, starting tile, and world position.
	If p_under_construction is true, the structure starts as a ghost with 1 HP.
	"""
	config = structure_config
	player_id = p_player_id
	current_tile = p_current_tile
	is_under_construction = p_under_construction
	construction_cost = config.get("cost", 0.0)

	# Initialize core stats from config
	size_hex = config.get("size", 0.0)
	max_health = config.get("max_health", 100.0)
	health = 1.0 if is_under_construction else max_health
	display_name = config.get("display_name", "Structure")
	structure_type = p_structure_type

	# Set position to planar world position for now. Height will be corrected after adding to tree.
	position = Vector3(world_pos.x, world_pos.y, world_pos.z)

	# Setup Mesh and Health Bar
	_setup_mesh(config)
	_setup_health_bar()

	# Apply ghost material if under construction
	if is_under_construction:
		_apply_ghost_material()

	# Setup specific functionalities (timers don't autostart if under construction)

	resource_generation_rate = config.get("resource_generation_rate", 0.0)
	if resource_generation_rate > 0.0:
		_setup_resource_timer()

	if config.has("produces_unit_type"):
		print("Structure %s: Detected unit production capability." % display_name)
		produces_unit_type = config.get("produces_unit_type", "")
		production_time = config.get("production_time", 5.0)
		_setup_production_timer()

	attack_damage = config.get("attack_damage", 0.0)
	attack_range_hex = config.get("attack_range", 0.0)
	attack_cooldown = config.get("attack_cooldown", 0.0)
	if attack_damage > 0.0 and attack_range_hex > 0.0:
		_setup_attack_timer()
		_setup_muzzle_flash()

	# Base structures get a builder spawn timer
	if config.get("category") == "base" and not is_under_construction:
		_setup_builder_spawn_timer()


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

	# Save the original material for later use in selection feedback
	original_material = mesh_instance.material_override

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
	resource_timer.autostart = not is_under_construction
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

func _setup_attack_timer():
	attack_check_timer = Timer.new()
	attack_check_timer.name = "AttackCheckTimer"
	attack_check_timer.wait_time = 0.25
	attack_check_timer.autostart = not is_under_construction
	attack_check_timer.connect("timeout", _on_attack_check_timeout)
	add_child(attack_check_timer)

func _setup_muzzle_flash():
	muzzle_flash = OmniLight3D.new()
	muzzle_flash.name = "MuzzleFlash"
	muzzle_flash.light_energy = 0.0
	muzzle_flash.omni_range = 0.5
	muzzle_flash.light_color = Color(1.0, 0.7, 0.3)
	add_child(muzzle_flash)

	muzzle_flash_timer = Timer.new()
	muzzle_flash_timer.name = "MuzzleFlashTimer"
	muzzle_flash_timer.wait_time = 0.15
	muzzle_flash_timer.one_shot = true
	muzzle_flash_timer.connect("timeout", _on_muzzle_flash_timeout)
	add_child(muzzle_flash_timer)

# --- Base Builder Queue ---

const GameData = preload("res://data/game_data.gd")

func _setup_builder_spawn_timer():
	if is_instance_valid(builder_spawn_timer):
		return
	builder_spawn_timer = Timer.new()
	builder_spawn_timer.name = "BuilderSpawnTimer"
	builder_spawn_timer.wait_time = GameData.BUILDER_CONFIG.spawn_interval
	builder_spawn_timer.autostart = true
	builder_spawn_timer.connect("timeout", _on_builder_spawn_timeout)
	add_child(builder_spawn_timer)

func get_resource_request() -> float:
	"""
	Returns how many resources are still needed for this structure.
	Accounts for resources already in transit via builders.
	"""
	if not is_under_construction or resources_pending <= 0:
		return 0.0
	return maxf(0.0, resources_pending - resources_in_transit)

func add_to_construction_queue(target: Node, type: String):
	construction_queue.append({"target": target, "type": type})
	print("Base %s (Player %d): Added %s to construction queue. Queue size: %d" % [display_name, player_id, type, construction_queue.size()])

func _on_builder_spawn_timeout():
	"""
	Called periodically by the base to send builders.
	Scans all structures and roads for requests, sends to closest with need.
	"""
	# Only bases can spawn builders
	if config.get("category") != "base":
		return

	if not is_instance_valid(grid):
		return

	# Get player
	var map_node = get_parent()
	var game_node = map_node.get_parent()
	if not is_instance_valid(game_node) or game_node.name != "Game":
		return

	var player: Player = game_node.get_player(player_id)
	if not is_instance_valid(player):
		return

	# Collect all structures and roads with active resource requests
	var requests: Array = []  # Array of {target, type, request_amount, distance}

	# Check all structures for this player
	for structure in player.structures:
		if not is_instance_valid(structure):
			continue
		if not structure.is_under_construction:
			continue

		var struct_request = structure.get_resource_request()
		if struct_request <= 0:
			continue

		var struct_dist = current_tile.get_coords().distance_to(structure.current_tile.get_coords())
		requests.append({
			"target": structure,
			"type": "structure",
			"request_amount": struct_request,
			"distance": struct_dist,
			"target_tile": structure.current_tile
		})

	# Check road construction tiles registered by this player
	# (The global construction_recovery_timer in Game.gd keeps this list accurate)
	for tile in player.road_construction_tiles:
		if not is_instance_valid(tile) \
				or not tile.road_under_construction \
				or player_id not in tile.road_builders:
			continue
		if tile.road_resources_pending <= 0:
			continue

		# Validate that this road tile has at least one walkable neighbor (can be built from)
		var has_walkable_neighbor = false
		for neighbor in tile.neighbors:
			if is_instance_valid(neighbor) and neighbor.walkable and neighbor.cost < 1e20:
				has_walkable_neighbor = true
				break
		if not has_walkable_neighbor:
			continue

		var road_request = tile.get_road_resource_request()
		if road_request <= 0:
			continue

		var road_dist = current_tile.get_coords().distance_to(tile.get_coords())
		requests.append({
			"target": tile,
			"type": "road",
			"request_amount": road_request,
			"distance": road_dist,
			"target_tile": tile
		})

	if requests.is_empty():
		return

	# Sort by distance (closest first)
	requests.sort_custom(func(a, b): return a["distance"] < b["distance"])

	# Send builder to the closest request
	var request = requests[0]
	var target = request["target"]
	var target_tile = request["target_tile"]
	var request_amount = request["request_amount"]
	var req_type = request["type"]

	var max_carry: float = GameData.BUILDER_CONFIG.max_carry
	var carry_amount = minf(max_carry, request_amount)

	if carry_amount <= 0:
		return

	# Check if player has enough resources
	if player.resources < carry_amount:
		return

	# Handle destination tiles - structures use the tile itself if walkable, roads always use a neighbor
	var destination_tile = target_tile
	const INF: float = 1e20

	if not destination_tile.walkable or destination_tile.cost >= INF:
		var closest_neighbor = null
		var closest_distance = INF
		var base_coords = current_tile.get_coords()
		for neighbor in destination_tile.neighbors:
			if is_instance_valid(neighbor) and neighbor.walkable and neighbor.cost < INF:
				var neighbor_dist = base_coords.distance_to(neighbor.get_coords())
				if neighbor_dist < closest_distance:
					closest_distance = neighbor_dist
					closest_neighbor = neighbor
		if closest_neighbor == null:
			push_warning("Base %s: No walkable neighbor found for construction target at %s" % [display_name, target_tile.get_coords()])
			return
		destination_tile = closest_neighbor

	# Find path (walkable-only: builders cannot cross water without a road)
	var path = grid.find_path(current_tile.get_coords(), destination_tile.get_coords(), true)
	if path.is_empty():
		push_warning("Base %s: No walkable path to construction target at %s" % [display_name, destination_tile.get_coords()])
		return
	# Always remove the starting tile (base position) from the path
	if path.size() > 0:
		path = path.slice(1)

	# Create and spawn builder
	var spawn_pos = current_tile.world_pos
	var target_structure = null
	if req_type == "structure":
		target_structure = target

	var builder = Builder.new(player_id, target_tile, target_structure, path, carry_amount, spawn_pos)
	map_node.add_child(builder)

	# Register and deduct resources
	player.builders.append(builder)
	player.add_resources(-carry_amount)

	# Track resources in transit
	if req_type == "structure":
		target.resources_in_transit += carry_amount
	elif req_type == "road":
		target.road_resources_in_transit += carry_amount

	print("Base %s (Player %d): Spawned builder carrying %.1f to %s (request: %.1f, in transit: %.1f)" % [
		display_name, player_id, carry_amount, req_type,
		request_amount,
		target.resources_in_transit if req_type == "structure" else target.road_resources_in_transit
	])

# --- Construction Logic ---

func _apply_ghost_material():
	"""
	Applies a semi-transparent ghost material to indicate the structure is under construction.
	"""
	if not is_instance_valid(mesh_instance):
		return
	ghost_material = StandardMaterial3D.new()
	ghost_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ghost_material.albedo_color = Color(0.5, 0.7, 1.0, 0.4)
	ghost_material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	mesh_instance.material_override = ghost_material

func add_construction_progress(hp_amount: float):
	"""
	Adds HP from a builder arrival. Completes construction when max_hp is reached.
	"""
	if not is_under_construction:
		return
	health = minf(health + hp_amount, max_health)
	if is_instance_valid(health_bar):
		health_bar.update_health(health, max_health)
	print("Structure %s: Construction progress %.1f / %.1f HP" % [display_name, health, max_health])
	if health >= max_health:
		_complete_construction()

func _complete_construction():
	"""
	Transitions from under-construction ghost to a fully operational structure.
	"""
	is_under_construction = false
	print("Structure %s (Player %d): Construction complete!" % [display_name, player_id])

	# Restore original material
	if is_instance_valid(mesh_instance):
		mesh_instance.material_override = original_material

	# Start resource generation timer if applicable
	if resource_generation_rate > 0.0 and is_instance_valid(resource_timer):
		resource_timer.start()

	# Start attack timer if applicable
	if attack_damage > 0.0 and attack_range_hex > 0.0 and is_instance_valid(attack_check_timer):
		attack_check_timer.start()

	# Start unit production if applicable
	if produces_unit_type != "":
		# Connect signal via Game node -> Player
		var game_node = get_parent().get_parent()
		if is_instance_valid(game_node) and game_node.name == "Game":
			var player = game_node.get_player(player_id)
			if is_instance_valid(player):
				if not unit_produced.is_connected(player._on_structure_unit_produced):
					unit_produced.connect(player._on_structure_unit_produced)
				start_production()

	# Newly completed bases get a builder spawn timer
	if config.get("category") == "base":
		_setup_builder_spawn_timer()

	# Refresh tile strategic dot now that this structure is fully placed
	if is_instance_valid(current_tile):
		current_tile._refresh_strategic_dot()

# --- Attack Logic ---

func _on_attack_check_timeout():
	if is_under_construction:
		return
	_try_attack()

func _on_muzzle_flash_timeout():
	if is_instance_valid(muzzle_flash):
		muzzle_flash.light_energy = 0.0

func _rotate_to_face(direction: Vector3):
	var planar = Vector2(direction.x, direction.z).normalized()
	if planar != Vector2.ZERO:
		rotation.y = atan2(planar.x, planar.y)

func _try_attack():
	var current_time = Time.get_unix_time_from_system()
	if (current_time - last_attack_time) < attack_cooldown:
		return

	var target_tile = _find_enemy_tile_in_range()
	if not is_instance_valid(target_tile):
		return

	# Rotate to face the target
	var target_world = Vector3(target_tile.world_pos.x, position.y, target_tile.world_pos.z)
	_rotate_to_face(target_world - position)

	# Deal damage to one enemy target (unit takes priority over structure)
	var hit_target: Node3D = null
	for unit_ref in target_tile.occupied_slots:
		if is_instance_valid(unit_ref) and unit_ref.player_id != player_id:
			hit_target = unit_ref
			break
	if hit_target == null and target_tile.structure != null \
			and is_instance_valid(target_tile.structure) \
			and target_tile.structure.player_id != player_id:
		hit_target = target_tile.structure
	if hit_target != null:
		hit_target.take_damage(attack_damage)

	# Damage road on the attacked tile
	if target_tile.has_road:
		target_tile.damage_road(attack_damage)

	# Muzzle flash
	if is_instance_valid(muzzle_flash):
		muzzle_flash.light_energy = 1.0
		muzzle_flash_timer.start()

	last_attack_time = current_time

func _find_enemy_tile_in_range() -> Tile:
	if not is_instance_valid(current_tile) or not is_instance_valid(grid):
		return null

	var max_hex_distance: int = ceil(attack_range_hex)
	if max_hex_distance <= 0:
		return null

	var attack_range_world: float = attack_range_hex * Grid.HEX_SCALE
	var attack_range_world_sq: float = attack_range_world * attack_range_world
	var self_pos: Vector3 = position

	var closest_tile: Tile = null
	var min_distance_sq: float = attack_range_world_sq + 1.0

	var current_x: int = current_tile.x
	var current_z: int = current_tile.z

	for x in range(current_x - max_hex_distance, current_x + max_hex_distance + 1):
		for z in range(current_z - max_hex_distance, current_z + max_hex_distance + 1):
			var tile_coords = Vector2i(x, z)
			if not grid.is_valid_coords(tile_coords):
				continue

			var tile_ref: Tile = grid.get_tile_by_coords(tile_coords)
			if not is_instance_valid(tile_ref):
				continue

			# Check if tile has enemy units or an enemy structure
			var has_enemy = false
			for unit_ref in tile_ref.occupied_slots:
				if is_instance_valid(unit_ref) and unit_ref.player_id != player_id:
					has_enemy = true
					break
			if not has_enemy:
				if tile_ref.structure != null \
						and is_instance_valid(tile_ref.structure) \
						and tile_ref.structure.player_id != player_id:
					has_enemy = true

			if not has_enemy:
				continue

			# Use tile center distance for tile-level targeting
			var distance_sq = self_pos.distance_squared_to(Vector3(tile_ref.world_pos.x, self_pos.y, tile_ref.world_pos.z))
			if distance_sq <= attack_range_world_sq and distance_sq < min_distance_sq:
				min_distance_sq = distance_sq
				closest_tile = tile_ref

	return closest_tile

# --- Resource Generation Logic ---

func _on_resource_timer_timeout():
	"""
	Generates resources for the owning player by finding the Game node and Player instance.
	"""
	if resource_generation_rate <= 0 or not resource_generation_enabled or is_under_construction:
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
	Checks if the owning player can afford the unit cost, deducts it, and starts the
	production timer. If the player cannot afford the unit, waits 1 second and retries.
	"""
	if produces_unit_type.is_empty():
		return

	var unit_config = GameData.UNIT_TYPES.get(produces_unit_type)
	if not unit_config:
		push_error("Unit Producer %s: unknown unit type '%s'." % [display_name, produces_unit_type])
		return

	var cost: float = unit_config.get("cost", 0.0)
	var game_node = get_parent().get_parent()
	if is_instance_valid(game_node) and game_node.name == "Game" and cost > 0.0:
		var player: Player = game_node.get_player(player_id)
		if is_instance_valid(player):
			if player.resources < cost:
				# Not enough resources — retry after a short delay
				is_waiting_for_resources = true
				is_producing = false
				production_timer.wait_time = 1.0
				production_timer.start()
				return
			player.add_resources(-cost)

	is_waiting_for_resources = false
	is_producing = true
	production_timer.wait_time = production_time
	production_timer.start()
	print("Structure %s (Player %d) started producing %s. Time: %f" % [display_name, player_id, produces_unit_type, production_time])

func _on_production_timer_timeout():
	"""
	Callback when a unit is finished producing (or when retrying after insufficient resources).
	On a resource-wait retry, calls start_production() again. Otherwise emits the unit_produced
	signal and restarts production for the next unit.
	"""
	if is_waiting_for_resources:
		start_production()
		return

	if not is_producing or not unit_production_enabled or is_under_construction:
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

				# Fix: Remove self from structures_by_coord dictionary
				if current_tile:
					var coords = current_tile.get_coords()
					if player.structures_by_coord.has(coords):
						player.structures_by_coord.erase(coords)

		# 2. Release current_tile.structure reference
		if current_tile and current_tile.structure == self:
			
			# Restore tile visibility if it was hidden by this structure
			if config.get("hide_tile", false):
				current_tile.set_tile_visibility(true)
			
			# Restore hole visibility if it was drilled by this structure
			if config.get("drill_hole", false):
				current_tile.set_hole_visibility(false)
				
			current_tile.structure = null

		# Refresh tile strategic dot (tile is now unoccupied by this structure)
		if current_tile != null:
			current_tile._refresh_strategic_dot()

		# Emit destruction signal before cleanup
		emit_signal("destroyed", self)

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

	# Apply current strategic zoom state
	var game_node = get_parent().get_parent()
	if is_instance_valid(game_node) and game_node.has_method("get_strategic_zoom"):
		set_strategic_zoom(game_node.get_strategic_zoom())


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
	var structure_height = get_structure_height()

	# Get vertical offset configuration (0.0 for resting on ground, negative to sink)
	var y_offset_fraction = config.get("y_offset_fraction", 0.0)

	# Calculate final Y position: Ground Y + Half Height (to center on ground) + Total height * Offset fraction
	# If y_offset_fraction is -0.5, position.y = ground_y (sinks structure center to ground level, halfway down)
	position.y = ground_y + (structure_height * y_offset_fraction)

# --- Production Control Methods ---

func set_strategic_zoom(is_strategic: bool) -> void:
	if is_instance_valid(mesh_instance):
		mesh_instance.visible = not is_strategic
	if is_instance_valid(health_bar):
		health_bar.visible = not is_strategic

func toggle_resource_generation():
	"""
	Toggles resource generation on/off.
	"""
	resource_generation_enabled = not resource_generation_enabled
	print("Structure %s: Resource generation %s" % [display_name, "enabled" if resource_generation_enabled else "disabled"])

func toggle_unit_production():
	"""
	Toggles unit production on/off.
	"""
	unit_production_enabled = not unit_production_enabled
	print("Structure %s: Unit production %s" % [display_name, "enabled" if unit_production_enabled else "disabled"])
	if unit_production_enabled and not is_producing and not is_waiting_for_resources:
		start_production()

func set_selected(selected: bool):
	"""
	Sets the selection state for this structure. Used for visual feedback.
	Applies a highlight material when selected, restores original material when deselected.
	"""
	is_selected = selected

	if not is_instance_valid(mesh_instance):
		return

	if selected:
		# Create a highlighted material if not already created
		if selected_material == null:
			selected_material = StandardMaterial3D.new()
			selected_material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
			selected_material.albedo_color = Color(1.0, 1.0, 0.0, 1.0)  # Yellow highlight
			selected_material.emission_enabled = true
			selected_material.emission = Color(1.0, 1.0, 0.5, 1.0)
			selected_material.emission_energy_multiplier = 1.5
		mesh_instance.material_override = selected_material
	else:
		# Restore the appropriate material
		if is_under_construction:
			mesh_instance.material_override = ghost_material
		else:
			mesh_instance.material_override = original_material
