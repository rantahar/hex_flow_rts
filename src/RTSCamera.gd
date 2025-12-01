extends Camera3D

# Signals
signal hex_clicked(world_position: Vector3)

# Constants
const STEP_SIZE = 0.3
const EDGE_THRESHOLD = 20.0
const ZOOM_SPEED = 0.5
const ZOOM_MIN = 1.0
const ZOOM_MAX = 50.0

# State variables
var is_middle_mouse_down: bool = false
var last_mouse_position: Vector2 = Vector2.ZERO

func _ready():
	# Ensure the camera is set up for 3D navigation
	# Using 'ui' actions for movement, ensure they are mapped in Project Settings -> Input Map
	make_current()

func _process(delta):
	# Movement (WASD/Arrows + Edge Scrolling)
	_handle_movement(delta)

func _input(event):
	# Middle Mouse Drag Handling
	_handle_middle_mouse_drag(event)

	# Zoom Handling
	_handle_zoom(event)

	# Left Click Raycasting
	_handle_raycast_click(event)

func _handle_movement(delta: float):
	# Handle key and edge movement
	var direction = Vector3.ZERO
	var viewport = get_viewport()
	var viewport_size = viewport.size

	# 1. Key Movement (WASD/Arrows)
	# Assuming default Godot input map actions or standard names
	if Input.is_action_pressed("ui_up"):
		direction -= transform.basis.z
	if Input.is_action_pressed("ui_down"):
		direction += transform.basis.z
	if Input.is_action_pressed("ui_left"):
		direction -= transform.basis.x
	if Input.is_action_pressed("ui_right"):
		direction += transform.basis.x

	# 3. Edge Scrolling
	var mouse_pos_vp = viewport.get_mouse_position()

	if mouse_pos_vp.x < EDGE_THRESHOLD:
		direction -= transform.basis.x
	elif mouse_pos_vp.x > viewport_size.x - EDGE_THRESHOLD:
		direction += transform.basis.x

	if mouse_pos_vp.y < EDGE_THRESHOLD:
		direction -= transform.basis.z
	elif mouse_pos_vp.y > viewport_size.y - EDGE_THRESHOLD:
		direction += transform.basis.z

	# Apply movement if any direction is pressed/active
	if direction != Vector3.ZERO:
		# Ignore Y movement, we only want to pan in the XZ plane
		direction.y = 0
		
		# Normalize and scale movement vector
		# Multiplying by 60.0 ensures movement is frame-rate independent and matches typical physics update rate
		var final_direction = direction.normalized() * STEP_SIZE * delta * 60.0 

		# Apply translation
		position += final_direction

func _handle_middle_mouse_drag(event):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			is_middle_mouse_down = event.pressed
			if event.pressed:
				last_mouse_position = get_viewport().get_mouse_position()
	
	if is_middle_mouse_down and event is InputEventMouseMotion:
		var current_mouse_position = get_viewport().get_mouse_position()
		var delta_mouse = current_mouse_position - last_mouse_position
		
		# Panning sensitivity
		var pan_speed = STEP_SIZE * 0.1

		# Translate the camera based on mouse movement (inverse direction for drag)
		# Pan in camera X direction (sideways)
		var pan_x = transform.basis.x * -delta_mouse.x * pan_speed
		# Pan in camera Z direction (forward/backward movement on screen Y axis)
		var pan_z = transform.basis.z * delta_mouse.y * pan_speed
		
		# Ensure panning only occurs in the XZ plane (ground level)
		pan_x.y = 0
		pan_z.y = 0
		
		position += pan_x + pan_z
		last_mouse_position = current_mouse_position

func _handle_zoom(event):
	if event is InputEventMouseButton:
		var zoom_delta = 0.0
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			zoom_delta = -1.0 # Zoom in
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			zoom_delta = 1.0 # Zoom out
		
		if zoom_delta != 0.0:
			var zoom_vector = transform.basis.z * ZOOM_SPEED * zoom_delta
			var new_position = position + zoom_vector
			
			# Clamp zoom based on Y position (assuming camera is pitched down)
			if new_position.y >= ZOOM_MIN and new_position.y <= ZOOM_MAX:
				position = new_position
			# Ensure we respect the limits if we try to zoom past them
			elif new_position.y < ZOOM_MIN:
				position.y = ZOOM_MIN
			elif new_position.y > ZOOM_MAX:
				position.y = ZOOM_MAX

func _handle_raycast_click(event):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		
		var mouse_pos_vp = get_viewport().get_mouse_position()
		
		# Get ray origin and direction from the camera
		var ray_origin = project_ray_origin(mouse_pos_vp)
		var ray_direction = project_ray_normal(mouse_pos_vp)
		
		# Raycast against the ground plane (y=0)
		var ground_plane = Plane(Vector3.UP, Vector3.ZERO)
		
		# Check if the ray intersects the plane
		var intersection_point = ground_plane.intersects_ray(ray_origin, ray_direction)
		
		if intersection_point != null:
			# Emit signal
			emit_signal("hex_clicked", intersection_point)

			# Debug visualization: print the hit position
			print("Hex Clicked at: ", intersection_point)
			
