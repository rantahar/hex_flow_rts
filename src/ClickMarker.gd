extends MeshInstance3D

const MARKER_LIFETIME = 2.0

@export var camera_path: NodePath
var camera_node: Node3D = null

func _ready():
	"""
	Called when the node is added to the scene tree.
	Connects to the `hex_clicked` signal of the RTSCamera node, if the path is valid.
	"""
	# Connect to the RTSCamera's signal if the path is provided
	if not camera_path.is_empty():
		camera_node = get_node_or_null(camera_path)
		
		# Check if the node is found and has the expected signal
		if camera_node and camera_node.has_signal("hex_clicked"):
			if not camera_node.hex_clicked.is_connected(_on_hex_clicked):
				camera_node.hex_clicked.connect(_on_hex_clicked)
		else:
			push_error("RTSCamera node not found at path '"+str(camera_path)+"' or does not emit 'hex_clicked'. Marker functionality disabled.")

func _on_hex_clicked(tile: Tile):
	"""
	Handles the `hex_clicked` signal from the camera. Moves the marker to the clicked tile's position,
	makes it visible, and starts a timer to hide it after a set duration.

	Arguments:
	- tile (Tile): The Tile object that was clicked.
	"""
	if not tile:
		return
		
	# Move the existing visual marker (self) to the calculated location
	# Use tile center XZ coordinates and add a small Y offset (0.1) for visibility above the tile
	global_position = tile.world_pos + Vector3(0, 0.1, 0)
	# Make marker visible on click
	visible = true
	# Reset the timer
	var timer = get_tree().create_timer(MARKER_LIFETIME)
	# Connect the timer to hide the marker after the timeout.
	timer.timeout.connect(_on_timer_timeout)

func _on_timer_timeout():
	"""
	Callback for the visibility timer. Hides the click marker.
	"""
	# Hide the marker.
	visible = false
