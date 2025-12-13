extends VBoxContainer

signal structure_selected(structure_key: String)

const GameData = preload("res://data/game_data.gd")
const Player = preload("res://src/Player.gd")

var player: Player
var buildable_structures: Dictionary = {}
var status_timer: Timer

func _ready():
	mouse_filter = Control.MOUSE_FILTER_STOP
	
	# 1. Initialize timer for status printing
	status_timer = Timer.new()
	status_timer.wait_time = 1.0
	status_timer.autostart = true
	status_timer.timeout.connect(_on_status_timer_timeout)
	add_child(status_timer)
	
	# 2. Generate buttons
	for key in GameData.STRUCTURE_TYPES:
		var config = GameData.STRUCTURE_TYPES[key]
		# Store config for easy lookup (All structures are now displayed)
		buildable_structures[key] = config
		
		var button = Button.new()
		button.mouse_filter = Control.MOUSE_FILTER_STOP
		button.name = key # Set button name to structure key for resource check lookup
		var cost = config.get("cost", 0)
		button.text = "%s (%d)" % [config.display_name, cost]
		button.pressed.connect(_on_build_button_pressed.bind(key))
		add_child(button)

func setup(p_player: Player):
	"""
	Sets the player reference and connects necessary signals.
	"""
	if not is_instance_valid(p_player):
		push_error("BuildMenu.setup: Invalid Player instance provided.")
		return
		
	player = p_player
	
	# Connect to resource updates
	if player.has_signal("resources_updated"):
		player.resources_updated.connect(_on_resources_updated)
		
	# Initial button state update
	_on_resources_updated(player.resources)

func _on_resources_updated(new_resources: float):
	"""
	Updates the enabled/disabled state of build buttons based on player resources.
	"""
	for button in get_children():
		if button is Button:
			var key = button.name
			if buildable_structures.has(key):
				var cost = buildable_structures[key].get("cost", 0.0)
				button.disabled = new_resources < cost

func _on_build_button_pressed(structure_key: String):
	"""
	Emits the structure_selected signal with the structure key.
	"""
	print("BuildMenu: Structure selected: %s" % structure_key)
	structure_selected.emit(structure_key)

func _on_status_timer_timeout():
	"""
	Prints status to console every 1 second.
	"""
	if is_instance_valid(player):
		print("BuildMenu Status - Player %d Resources: %0.2f" % [player.id, player.resources])
	else:
		print("BuildMenu Status - Player not set up.")
