extends VBoxContainer
class_name ProductionControlUI

var game_node: Node = null
var selected_structures: Array[Structure] = []

@onready var selection_label: Label
@onready var select_all_button: Button
@onready var resource_toggle: CheckButton
@onready var production_toggle: CheckButton

func _ready():
	# Create UI elements
	_create_ui()

	# Find Game node
	game_node = get_tree().get_root().find_child("Game", true, false)
	if game_node and game_node.has_signal("selection_changed"):
		game_node.selection_changed.connect(_on_selection_changed)

func _create_ui():
	"""
	Creates the UI elements for production control.
	"""
	# Selection info label
	selection_label = Label.new()
	selection_label.name = "SelectionLabel"
	selection_label.text = "No structures selected"
	add_child(selection_label)

	# Select All button
	select_all_button = Button.new()
	select_all_button.name = "SelectAllButton"
	select_all_button.text = "Select All of Type"
	select_all_button.disabled = true
	select_all_button.pressed.connect(_on_select_all_pressed)
	add_child(select_all_button)

	# Resource generation toggle
	resource_toggle = CheckButton.new()
	resource_toggle.name = "ResourceToggle"
	resource_toggle.text = "Resource Generation"
	resource_toggle.disabled = true
	resource_toggle.button_pressed = true
	resource_toggle.toggled.connect(_on_resource_toggle_pressed)
	add_child(resource_toggle)

	# Unit production toggle
	production_toggle = CheckButton.new()
	production_toggle.name = "ProductionToggle"
	production_toggle.text = "Unit Production"
	production_toggle.disabled = true
	production_toggle.button_pressed = true
	production_toggle.toggled.connect(_on_production_toggle_pressed)
	add_child(production_toggle)

func _on_selection_changed(structures: Array[Structure]):
	"""
	Called when the selection changes. Updates UI state.
	"""
	selected_structures = structures

	if structures.is_empty():
		# No selection
		selection_label.text = "No structures selected"
		select_all_button.disabled = true
		resource_toggle.disabled = true
		production_toggle.disabled = true
		return

	# Update selection label
	var count = structures.size()
	if count == 1:
		var structure = structures[0]
		selection_label.text = "1 %s selected" % structure.display_name
		select_all_button.text = "Select All %ss" % structure.display_name
	else:
		# Check if all selected structures are the same type
		var first_type = structures[0].structure_type
		var all_same_type = true
		for structure in structures:
			if structure.structure_type != first_type:
				all_same_type = false
				break

		if all_same_type:
			selection_label.text = "%d %ss selected" % [count, structures[0].display_name]
			select_all_button.text = "Select All %ss" % structures[0].display_name
		else:
			selection_label.text = "%d structures selected" % count
			select_all_button.text = "Select All of Type"

	# Enable buttons
	select_all_button.disabled = false
	resource_toggle.disabled = false
	production_toggle.disabled = false

	# Update toggle states based on first selected structure
	# (If mixed states exist, we'll show the first structure's state)
	if not structures.is_empty():
		resource_toggle.set_pressed_no_signal(structures[0].resource_generation_enabled)
		production_toggle.set_pressed_no_signal(structures[0].unit_production_enabled)

func _on_select_all_pressed():
	"""
	Selects all structures of the same type as the currently selected ones.
	"""
	if selected_structures.is_empty():
		return

	var structure_type = selected_structures[0].structure_type
	if game_node and game_node.has_method("select_all_of_type"):
		game_node.select_all_of_type(structure_type)

func _on_resource_toggle_pressed(pressed: bool):
	"""
	Toggles resource generation for all selected structures.
	"""
	for structure in selected_structures:
		structure.resource_generation_enabled = pressed
		print("Structure %s: Resource generation %s" % [structure.display_name, "enabled" if pressed else "disabled"])

func _on_production_toggle_pressed(pressed: bool):
	"""
	Toggles unit production for all selected structures.
	"""
	for structure in selected_structures:
		structure.unit_production_enabled = pressed
		print("Structure %s: Unit production %s" % [structure.display_name, "enabled" if pressed else "disabled"])
