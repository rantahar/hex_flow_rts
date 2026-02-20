extends Camera3D
 
# Signals
signal hex_clicked(tile: Tile, button_index: int)
signal strategic_zoom_changed(is_strategic: bool)

# Dependencies
const GameConfig = preload("res://data/game_config.gd")
@export var grid_registry: Grid

# State variables
var is_middle_mouse_down: bool = false
var last_mouse_position: Vector2 = Vector2.ZERO
var map_bounds: Dictionary = {}
var _is_strategic_zoom: bool = false
 
func _ready():
	"""
	Called when the node enters the scene tree for the first time.
	Attempts to find and register the Grid node and retrieves the map boundaries for camera clamping.
	Sets this camera as the current viewport camera.
	"""
	if not is_instance_valid(grid_registry):
		# Attempt to find Grid dynamically, assuming Map is a sibling named "Map"
		var map_node = get_parent().find_child("Map", true, false)
		if map_node:
			grid_registry = map_node.get_node_or_null("Grid")
			if not is_instance_valid(grid_registry):
				push_error("Could not find Grid node under Map/Grid.")
		else:
			push_error("Could not find Map node.")

	if is_instance_valid(grid_registry):
		map_bounds = grid_registry.get_map_bounds()

	# Ensure the camera is set up for 3D navigation
	# Using 'ui' actions for movement, ensure they are mapped in Project Settings -> Input Map
	make_current()
	position.y = GameConfig.CAMERA_ZOOM_START
	_check_strategic_zoom()

func reset_to(tile: Tile, camera_height: float = GameConfig.CAMERA_ZOOM_START) -> void:
	"""
	Resets the camera to look at a tile at ground level.
	Positions the camera at the specified height such that a downward-looking ray
	(at -55 degrees pitch) passes through the tile center.

	Arguments:
	- tile: The Tile to center on
	- camera_height: The height above ground where the camera should be positioned
	"""
	if not is_instance_valid(tile):
		push_error("RTSCamera.reset_to: Invalid tile provided")
		return

	# Calculate horizontal distance using tan(55°) ≈ 1.428
	# distance = height / tan(angle)
	var pitch_angle_degrees = GameConfig.CAMERA_RESET_PITCH
	var pitch_angle_radians = deg_to_rad(pitch_angle_degrees)
	var horizontal_distance = camera_height / tan(pitch_angle_radians)

	# Position camera back and up from the target tile
	# Assuming camera looks forward (negative Z direction)
	var world_pos = tile.world_pos
	var cam_x = world_pos.x
	var cam_z = world_pos.z + horizontal_distance

	position = Vector3(cam_x, camera_height, cam_z)
	_clamp_position()
	

func _process(delta):
	"""
	Called every frame. Handles continuous camera movement via keyboard input or edge scrolling.

	Arguments:
	- delta (float): The elapsed time since the previous frame.
	"""
	# Movement (WASD/Arrows + Edge Scrolling)
	_handle_movement(delta)

func _unhandled_input(event):
	"""
	Handles various non-continuous input events like mouse clicks, mouse wheel, and middle-mouse button state changes.

	Arguments:
	- event (InputEvent): The incoming input event.
	"""
	# Middle Mouse Drag Handling
	_handle_middle_mouse_drag(event)

	# Zoom Handling
	_handle_zoom(event)

	# Left/Right Click Raycasting
	_handle_raycast_click(event)

func _handle_movement(delta: float):
	"""
	Calculates and applies camera panning movement based on key presses (WASD/Arrows) and mouse position (edge scrolling).
	The speed is dynamically adjusted based on the camera's height (position.y) to ensure constant screen-space movement.

	Arguments:
	- delta (float): The elapsed time since the previous frame.
	"""
	# Handle key and edge movement
	var direction = Vector3.ZERO
	var viewport = get_viewport()
	var viewport_size = viewport.size

	# Key Movement (uses ui_ actions)
	# Assuming default Godot input map actions or standard names
	if Input.is_action_pressed("ui_up"):
		direction -= transform.basis.z
	if Input.is_action_pressed("ui_down"):
		direction += transform.basis.z
	if Input.is_action_pressed("ui_left"):
		direction -= transform.basis.x
	if Input.is_action_pressed("ui_right"):
		direction += transform.basis.x

	# Edge Scrolling
	var mouse_pos_vp = viewport.get_mouse_position()

	if mouse_pos_vp.x < GameConfig.CAMERA_EDGE_THRESHOLD:
		direction -= transform.basis.x
	elif mouse_pos_vp.x > viewport_size.x - GameConfig.CAMERA_EDGE_THRESHOLD:
		direction += transform.basis.x

	if mouse_pos_vp.y < GameConfig.CAMERA_EDGE_THRESHOLD:
		direction -= transform.basis.z
	elif mouse_pos_vp.y > viewport_size.y - GameConfig.CAMERA_EDGE_THRESHOLD:
		direction += transform.basis.z

	# Apply movement if any direction is pressed/active
	if direction != Vector3.ZERO:
		# Ignore Y movement, we only want to pan in the XZ plane
		direction.y = 0
		
		# Normalize and scale movement vector
		# Calculate dynamic speed based on position.y to maintain constant screen-space movement regardless of zoom.
		var dynamic_speed = GameConfig.CAMERA_STEP_SIZE * position.y
		
		# Multiplying by 60.0 ensures movement is frame-rate independent and matches typical physics update rate
		var final_direction = direction.normalized() * dynamic_speed * delta * 60.0

		# Apply translation
		position += final_direction
		
		# Clamp camera position to map boundaries
		_clamp_position()

func _handle_middle_mouse_drag(event):
	"""
	Handles camera panning when the middle mouse button is held down and the mouse is moved.
	Movement speed is adjusted based on camera height.

	Arguments:
	- event (InputEvent): The incoming input event.
	"""
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			is_middle_mouse_down = event.pressed
			if event.pressed:
				last_mouse_position = get_viewport().get_mouse_position()
	
	if is_middle_mouse_down and event is InputEventMouseMotion:
		var current_mouse_position = get_viewport().get_mouse_position()
		var delta_mouse = current_mouse_position - last_mouse_position
		
		# Panning sensitivity. Scale by position.y to maintain constant screen-space drag sensitivity regardless of zoom.
		var pan_speed = GameConfig.CAMERA_STEP_SIZE * 0.1 * position.y

		# Translate the camera based on mouse movement (inverse direction for drag)
		# Pan in camera X direction (sideways)
		var pan_x = transform.basis.x * -delta_mouse.x * pan_speed
		# Pan in camera Z direction (forward/backward movement on screen Y axis)
		var pan_z = transform.basis.z * -delta_mouse.y * pan_speed
		
		# Ensure panning only occurs in the XZ plane (ground level)
		pan_x.y = 0
		pan_z.y = 0
		
		position += pan_x + pan_z
		last_mouse_position = current_mouse_position
		
		# Clamp camera position to map boundaries
		_clamp_position()

func _handle_zoom(event):
	"""
	Handles camera zooming (moving along the view vector) using the mouse wheel.
	The camera's Y position is clamped within defined GameConfig.CAMERA_ZOOM_MIN and GameConfig.CAMERA_ZOOM_MAX limits.

	Arguments:
	- event (InputEvent): The incoming input event.
	"""
	if event is InputEventMouseButton:
		var zoom_delta = 0.0
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			zoom_delta = -1.0 # Zoom in
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			zoom_delta = 1.0 # Zoom out
		
		if zoom_delta != 0.0:
			var zoom_vector = transform.basis.z * GameConfig.CAMERA_ZOOM_SPEED * zoom_delta
			var new_position = position + zoom_vector

			# Clamp zoom based on Y position (assuming camera is pitched down)
			if new_position.y >= GameConfig.CAMERA_ZOOM_MIN and new_position.y <= GameConfig.CAMERA_ZOOM_MAX:
				position = new_position
			# Ensure we respect the limits if we try to zoom past them
			elif new_position.y < GameConfig.CAMERA_ZOOM_MIN:
				position.y = GameConfig.CAMERA_ZOOM_MIN
			elif new_position.y > GameConfig.CAMERA_ZOOM_MAX:
				position.y = GameConfig.CAMERA_ZOOM_MAX
			_check_strategic_zoom()
				
func _check_strategic_zoom() -> void:
	var new_state: bool = position.y >= GameConfig.CAMERA_ZOOM_STRATEGIC
	if new_state != _is_strategic_zoom:
		_is_strategic_zoom = new_state
		emit_signal("strategic_zoom_changed", _is_strategic_zoom)

func _clamp_position():
	"""
	Clamps the camera position to keep the map visible.
	X: clamp directly (no pitch offset on the X axis).
	Z: clamp the projected ground center (where the camera's center ray hits y=0),
	   then shift the camera by the same offset. This accounts for the forward pitch
	   so the camera cannot scroll past the map edge.
	"""
	if map_bounds.is_empty():
		return

	# X: ground_x == position.x (camera has no left/right tilt), clamp directly
	position.x = clamp(position.x, map_bounds.x_min, map_bounds.x_max)

	# Z: camera is pitched forward, so the visible ground center is ahead of position.z.
	# Project the center ray onto the ground plane (y=0) and clamp that point.
	var view_dir = -transform.basis.z  # camera looks in -local Z
	if abs(view_dir.y) > 0.001:
		var t = -position.y / view_dir.y  # ray parameter where y == 0
		var projected_z = position.z + t * view_dir.z
		var clamped_z = clamp(projected_z, map_bounds.z_min, map_bounds.z_max)
		position.z += clamped_z - projected_z
	else:
		position.z = clamp(position.z, map_bounds.z_min, map_bounds.z_max)

func _handle_raycast_click(event):
	"""
	Handles mouse button presses (left and right) by performing a raycast from the camera through the mouse position.
	If the raycast hits a tile body, it finds the associated Tile data object and emits the `hex_clicked` signal.

	Arguments:
	- event (InputEvent): The incoming input event.
	"""
	if event is InputEventMouseButton and (event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_RIGHT) and event.pressed:
		if not is_instance_valid(grid_registry):
			push_error("Grid registry not available in RTSCamera.gd")
			return
			
		var mouse_pos_vp = get_viewport().get_mouse_position()
		
		# Get ray origin and direction from the camera
		var ray_origin = project_ray_origin(mouse_pos_vp)
		var ray_end = ray_origin + project_ray_normal(mouse_pos_vp) * GameConfig.RAYCAST_LENGTH
		
		# Create ray query parameters
		var space = get_world_3d().space
		var query = PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
		
		# Check ONLY layer 0 (default) for tiles
		query.collide_with_areas = false
		query.collide_with_bodies = true
		query.collision_mask = 1 # Bit 0 is the default collision mask
		
		# Perform the raycast
		var result = PhysicsServer3D.space_get_direct_state(space).intersect_ray(query)
		
		if result:
			# Get collision object data
			var collider = result.collider
			
			# We need to find the registered Tile ancestor.
			var current_node: Node = collider
			var tile_coords: Vector2i = Vector2i(-1, -1)
			
			# Traverse up the tree until a registered node is found or we reach the root of the map generation.
			while current_node:
				if current_node is Tile: # Check for Tile class instead of StaticBody3D
					tile_coords = grid_registry.find_tile_by_node(current_node)
					if tile_coords != Vector2i(-1, -1):
						break
				
				# Optimization: Stop searching if we hit the top-level scene/map node
				if current_node.get_parent() is not Node: # Check if parent is null or not a regular node
					break
					
				current_node = current_node.get_parent()
			
			if tile_coords != Vector2i(-1, -1):
				# Look up Tile object
				var tile = grid_registry.tiles.get(tile_coords)
				
				if tile:
					# Emit signal with the Tile object and button pressed
					emit_signal("hex_clicked", tile, event.button_index)
