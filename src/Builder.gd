extends Node3D
class_name Builder

const GameData = preload("res://data/game_data.gd")

var player_id: int = 0
var resources_carried: float = 0.0
var target_tile: Tile = null
var target_structure: Structure = null  # null for road construction
var waypoints: Array[Vector2i] = []
var waypoint_index: int = 0
var current_tile: Tile = null
var grid: Grid = null
var mesh_instance: MeshInstance3D
var health_bar: HealthBar3D
var scale_factor: float = 1.0
var move_speed: float = 0.5
var is_moving: bool = false
var target_world_pos: Vector3 = Vector3.ZERO
var health: float = 20.0
var max_health: float = 20.0

var movement_timer: Timer
var stuck_time: float = 0.0

func _init(p_player_id: int, p_target_tile: Tile, p_target_structure: Structure, p_waypoints: Array[Vector2i], p_resources: float, spawn_pos: Vector3):
	print("Builder._init: Player %d, target=%s, waypoints=%d, resources=%.1f, spawn=%s" % [p_player_id, str(p_target_tile.get_coords()) if p_target_tile else "null", p_waypoints.size(), p_resources, spawn_pos])
	player_id = p_player_id
	target_tile = p_target_tile
	target_structure = p_target_structure
	waypoints = p_waypoints
	resources_carried = p_resources

	var builder_config = GameData.BUILDER_CONFIG
	move_speed = builder_config.get("move_speed", 0.5)
	max_health = builder_config.get("max_health", 20.0)
	health = max_health

	position = spawn_pos

	_setup_mesh(builder_config)
	_setup_health_bar()
	_setup_movement_timer()

func _setup_mesh(builder_config: Dictionary) -> void:
	var mesh_path: String = builder_config.get("mesh_path", "")
	var mesh: Mesh = load(mesh_path)
	if not mesh:
		push_error("Builder: Failed to load mesh at path: %s" % mesh_path)
		return

	mesh_instance = MeshInstance3D.new()
	mesh_instance.name = "BuilderMeshInstance"
	mesh_instance.mesh = mesh

	var size_hex: float = builder_config.get("size", 0.05)
	var target_world_radius: float = Grid.HEX_SCALE * size_hex
	var aabb_size: Vector3 = mesh.get_aabb().size
	var current_mesh_radius: float = maxf(aabb_size.x, aabb_size.z) / 2.0

	if current_mesh_radius > 0:
		scale_factor = target_world_radius / current_mesh_radius
	else:
		scale_factor = 1.0

	mesh_instance.scale = Vector3(scale_factor, scale_factor, scale_factor)
	add_child(mesh_instance)

func _setup_health_bar() -> void:
	health_bar = HealthBar3D.new()
	add_child(health_bar)
	if is_instance_valid(mesh_instance) and mesh_instance.mesh:
		var mesh_aabb_size: Vector3 = mesh_instance.mesh.get_aabb().size
		var scaled_size: Vector3 = mesh_aabb_size * scale_factor
		health_bar.setup(scaled_size)
	health_bar.update_health(health, max_health)

func _setup_movement_timer() -> void:
	movement_timer = Timer.new()
	movement_timer.wait_time = 0.5
	movement_timer.autostart = true
	movement_timer.connect("timeout", _on_movement_check_timeout)
	add_child(movement_timer)

func _ready():
	var map_node = get_parent()
	if map_node and is_instance_valid(map_node.get_node_or_null("Grid")):
		grid = map_node.get_node("Grid")
	_correct_height()

	# Apply current strategic zoom state
	var game_node = get_parent().get_parent()
	if is_instance_valid(game_node) and game_node.has_method("get_strategic_zoom"):
		set_strategic_zoom(game_node.get_strategic_zoom())

func set_strategic_zoom(is_strategic: bool) -> void:
	if is_instance_valid(mesh_instance):
		mesh_instance.visible = not is_strategic
	if is_instance_valid(health_bar):
		health_bar.visible = not is_strategic

func _correct_height():
	var map_node = get_parent()
	if not is_instance_valid(map_node) or not map_node.has_method("get_height_at_world_pos"):
		return
	var ground_y = map_node.get_height_at_world_pos(position)
	var unit_height = get_builder_height()
	position.y = ground_y + unit_height / 2.0

func get_builder_height() -> float:
	if mesh_instance and mesh_instance.mesh:
		var aabb_size: Vector3 = mesh_instance.mesh.get_aabb().size
		return aabb_size.y * scale_factor
	return 0.0

func _on_movement_check_timeout():
	if not is_moving:
		_advance_to_next_waypoint()

func _physics_process(delta):
	if not is_moving:
		stuck_time += delta
		if stuck_time >= 1.0:
			_on_stuck()
		return

	stuck_time = 0.0

	var target_destination: Vector3 = target_world_pos

	# Effective speed based on tile cost
	var tile_cost: float = 1.0
	if is_instance_valid(current_tile):
		if current_tile.has_road and not current_tile.road_under_construction:
			tile_cost = GameData.ROAD_CONFIG.road_tile_cost
		else:
			tile_cost = current_tile.cost

	var effective_speed: float = move_speed / maxf(tile_cost, 0.1)

	var movement_vector: Vector3 = target_destination - position
	var distance_to_target: float = movement_vector.length()
	var arrival_threshold: float = effective_speed * delta

	if distance_to_target < arrival_threshold:
		position = target_destination
		is_moving = false
		_advance_to_next_waypoint()
		return

	var direction: Vector3 = movement_vector.normalized()
	position += direction * effective_speed * delta

	# Rotate to face direction
	var planar_direction = Vector2(direction.x, direction.z).normalized()
	if planar_direction != Vector2.ZERO:
		rotation.y = atan2(planar_direction.x, planar_direction.y)

func _advance_to_next_waypoint():
	if not is_instance_valid(grid):
		return

	if waypoint_index >= waypoints.size():
		_on_arrival()
		return

	var next_coords = waypoints[waypoint_index]
	var next_tile = grid.tiles.get(next_coords)
	if not is_instance_valid(next_tile):
		push_error("Builder: Invalid tile at waypoint %s" % next_coords)
		return

	# Builders are blocked only by enemy military units
	if next_tile.has_enemy_units(player_id):
		return

	# Move to tile center — no formation slot needed
	if is_instance_valid(current_tile):
		current_tile.unregister_builder(self)
	next_tile.register_builder(self)
	current_tile = next_tile
	waypoint_index += 1

	var map_node = get_parent()
	var ground_y: float = 0.0
	if is_instance_valid(map_node) and map_node.has_method("get_height_at_world_pos"):
		ground_y = map_node.get_height_at_world_pos(next_tile.world_pos)

	target_world_pos = Vector3(next_tile.world_pos.x, ground_y, next_tile.world_pos.z)
	is_moving = true

func _on_stuck():
	print("Builder (Player %d): Stuck for too long, refunding %.1f resources." % [player_id, resources_carried])

	if is_instance_valid(current_tile):
		current_tile.unregister_builder(self)

	# Decrement in-transit counts
	if is_instance_valid(target_structure):
		target_structure.resources_in_transit = maxf(0.0, target_structure.resources_in_transit - resources_carried)
	elif is_instance_valid(target_tile):
		target_tile.road_resources_in_transit = maxf(0.0, target_tile.road_resources_in_transit - resources_carried)

	# Refund resources to player
	var map_node = get_parent()
	if is_instance_valid(map_node):
		var game_node = map_node.get_parent()
		if is_instance_valid(game_node) and game_node.name == "Game":
			var player = game_node.get_player(player_id)
			if is_instance_valid(player):
				player.add_resources(resources_carried)
				if player.has_method("_remove_builder"):
					player._remove_builder(self)

	queue_free()

func _on_arrival():
	if is_instance_valid(current_tile):
		current_tile.unregister_builder(self)

	if is_instance_valid(target_structure):
		# Check if structure is still under construction
		if target_structure.is_under_construction:
			# Structure construction: add HP and decrement resources in transit
			var hp_contribution = target_structure.max_health * resources_carried / maxf(target_structure.construction_cost, 1.0)
			target_structure.add_construction_progress(hp_contribution)
			target_structure.resources_in_transit = maxf(0.0, target_structure.resources_in_transit - resources_carried)
			target_structure.resources_pending = maxf(0.0, target_structure.resources_pending - resources_carried)
			print("Builder (Player %d): Delivered %.1f resources to %s, contributing %.1f HP (in transit now: %.1f, pending: %.1f)" % [player_id, resources_carried, target_structure.display_name, hp_contribution, target_structure.resources_in_transit, target_structure.resources_pending])
		else:
			# Structure already completed - refund resources
			var game_node = get_parent().get_parent()
			if is_instance_valid(game_node) and game_node.name == "Game":
				var player = game_node.get_player(player_id)
				if is_instance_valid(player):
					player.add_resources(resources_carried)
					print("Builder (Player %d): Structure %s already completed. Refunded %.1f resources." % [player_id, target_structure.display_name, resources_carried])
			target_structure.resources_in_transit = maxf(0.0, target_structure.resources_in_transit - resources_carried)
	elif is_instance_valid(target_tile):
		# Road construction: deliver resources, complete only when fully paid
		if target_tile.road_under_construction:
			target_tile.road_resources_in_transit = maxf(0.0, target_tile.road_resources_in_transit - resources_carried)
			target_tile.road_resources_pending = maxf(0.0, target_tile.road_resources_pending - resources_carried)
			print("Builder (Player %d): Delivered %.1f to road at %s (pending: %.1f)" % [player_id, resources_carried, target_tile.get_coords(), target_tile.road_resources_pending])
			if target_tile.road_resources_pending <= 0:
				target_tile.complete_road_construction()
				print("Builder (Player %d): Completed road at %s" % [player_id, target_tile.get_coords()])
		else:
			# Road already completed - refund resources
			var game_node = get_parent().get_parent()
			if is_instance_valid(game_node) and game_node.name == "Game":
				var player = game_node.get_player(player_id)
				if is_instance_valid(player):
					player.add_resources(resources_carried)
					print("Builder (Player %d): Road at %s already completed. Refunded %.1f resources." % [player_id, target_tile.get_coords(), resources_carried])
			target_tile.road_resources_in_transit = maxf(0.0, target_tile.road_resources_in_transit - resources_carried)

	# Remove from player's builders list
	var map_node = get_parent()
	if is_instance_valid(map_node):
		var game_node = map_node.get_parent()
		if is_instance_valid(game_node) and game_node.name == "Game":
			var player = game_node.get_player(player_id)
			if is_instance_valid(player) and player.has_method("_remove_builder"):
				player._remove_builder(self)

	queue_free()

func take_damage(amount: float):
	health -= amount
	health = maxf(0.0, health)

	if is_instance_valid(health_bar):
		health_bar.update_health(health, max_health)

	if health <= 0:
		if is_instance_valid(current_tile):
			current_tile.unregister_builder(self)

		# Decrement resources in transit since this builder won't arrive
		if is_instance_valid(target_structure):
			target_structure.resources_in_transit = maxf(0.0, target_structure.resources_in_transit - resources_carried)
			print("Builder (Player %d): Died before arrival. Decremented resources in transit for %s (now %.1f)" % [player_id, target_structure.display_name, target_structure.resources_in_transit])
		elif is_instance_valid(target_tile):
			target_tile.road_resources_in_transit = maxf(0.0, target_tile.road_resources_in_transit - resources_carried)
			print("Builder (Player %d): Died before arrival. Decremented road resources in transit (now %.1f)" % [player_id, target_tile.road_resources_in_transit])

		# Remove from player's builders list
		var map_node = get_parent()
		if is_instance_valid(map_node):
			var game_node = map_node.get_parent()
			if is_instance_valid(game_node) and game_node.name == "Game":
				var player = game_node.get_player(player_id)
				if is_instance_valid(player) and player.has_method("_remove_builder"):
					player._remove_builder(self)

		queue_free()
