extends MeshInstance3D

const MARKER_LIFETIME = 2.0

@export var camera_path: NodePath
var camera_node: Node3D = null

func _ready():
	# Connect to the RTSCamera's signal if the path is provided
	if not camera_path.is_empty():
		camera_node = get_node_or_null(camera_path)
		
		# Check if the node is found and has the expected signal
		if camera_node and camera_node.has_signal("hex_clicked"):
			if not camera_node.hex_clicked.is_connected(_on_hex_clicked):
				camera_node.hex_clicked.connect(_on_hex_clicked)
		else:
			push_error("RTSCamera node not found at path '"+str(camera_path)+"' or does not emit 'hex_clicked'. Marker functionality disabled.")

func _on_hex_clicked(tile_coords: Vector2i, world_position: Vector3, tile_node: Node3D):
	# Move the existing visual marker (self) to the clicked location
	# Use the raycast hit position to handle varying tile heights.
	global_position = world_position
	# Reset the timer
	var timer = get_tree().create_timer(MARKER_LIFETIME)
	# Connect the timer to a function for future visibility toggle (as requested)
	timer.timeout.connect(_on_timer_timeout)

func _on_timer_timeout():
	# Future implementation for turning visibility off will go here.
	pass
