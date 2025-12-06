extends HBoxContainer

const Player = preload("res://src/Player.gd")

var player: Player
var resource_label: Label

func _ready():
	# Find the Label child named "ResourceLabel"
	resource_label = get_node_or_null("ResourceLabel")
	if not resource_label:
		push_error("ResourceDisplay: Could not find 'ResourceLabel' child.")
		return
		
	# Update the display immediately if the player is already set (e.g., if setup() was called before _ready())
	if is_instance_valid(player):
		update_display(player.resources)

func setup(p_player: Player):
	"""
	Sets the player reference and connects the resources_updated signal.
	"""
	if not is_instance_valid(p_player):
		push_error("ResourceDisplay.setup: Invalid Player instance provided.")
		return
		
	player = p_player
	
	# Connect signal if the player instance is valid and has the signal (it should, we just added it)
	if player.has_signal("resources_updated"):
		player.resources_updated.connect(update_display)
		
	# Initial resource display
	update_display(player.resources)

func update_display(new_resources: float):
	"""
	Updates the displayed resource count.
	"""
	if is_instance_valid(resource_label):
		# Format to 2 decimal places
		resource_label.text = "Resources: %0.2f" % new_resources
