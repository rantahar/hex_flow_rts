extends VBoxContainer
class_name ProductionControlUI

const Structure = preload("res://src/core/Structure.gd")
const GameData = preload("res://data/game_data.gd")

var game_node: Node = null
var selected_structures: Array[Structure] = []

@onready var selection_label: Label
@onready var select_all_button: Button
@onready var resource_toggle: CheckButton
@onready var production_toggle: CheckButton

var info_panel: PanelContainer
var structure_image: TextureRect
var name_label: Label
var stats_label: Label
var production_progress: ProgressBar
var _info_structure: Structure = null

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
	# --- Info panel (shown only when a single structure is selected) ---
	info_panel = PanelContainer.new()
	info_panel.name = "InfoPanel"
	info_panel.visible = false
	add_child(info_panel)

	var hbox = HBoxContainer.new()
	info_panel.add_child(hbox)

	structure_image = TextureRect.new()
	structure_image.name = "StructureImage"
	structure_image.custom_minimum_size = Vector2(64, 64)
	structure_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	hbox.add_child(structure_image)

	var info_vbox = VBoxContainer.new()
	hbox.add_child(info_vbox)

	name_label = Label.new()
	name_label.name = "NameLabel"
	name_label.add_theme_font_size_override("font_size", 16)
	info_vbox.add_child(name_label)

	stats_label = Label.new()
	stats_label.name = "StatsLabel"
	stats_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_vbox.add_child(stats_label)

	# --- Production progress bar ---
	production_progress = ProgressBar.new()
	production_progress.name = "ProductionProgress"
	production_progress.min_value = 0.0
	production_progress.max_value = 100.0
	production_progress.value = 0.0
	production_progress.visible = false
	add_child(production_progress)

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

	if structures.size() == 1:
		_update_structure_info(structures[0])
		info_panel.visible = true
	else:
		info_panel.visible = false
		production_progress.visible = false
		_info_structure = null

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

func _update_structure_info(structure: Structure):
	"""
	Populates the info panel for a single selected structure.
	"""
	# Load texture from mesh path
	var mesh_path = structure.config.get("mesh_path", "")
	if mesh_path != "":
		var texture_path = mesh_path.replace(".obj", ".png")
		var tex = load(texture_path)
		structure_image.texture = tex
	else:
		structure_image.texture = null

	name_label.text = structure.display_name

	# Build stats string
	var stats := ""
	if structure.produces_unit_type != "":
		var unit_data = GameData.UNIT_TYPES.get(structure.produces_unit_type, {})
		var unit_display = unit_data.get("display_name", structure.produces_unit_type)
		var cost = unit_data.get("cost", 0)
		var state_str := "Idle"
		if structure.is_waiting_for_resources:
			state_str = "Waiting..."
		elif structure.is_producing:
			state_str = "Producing"
		stats = "Produces: %s\nCost: %d\n%s" % [unit_display, cost, state_str]
	elif structure.resource_generation_rate > 0 and structure.attack_damage == 0:
		stats = "Resources: +%d/sec" % int(structure.resource_generation_rate)
	elif structure.attack_damage > 0:
		stats = "Damage: %d\nRange: %d hex" % [structure.attack_damage, structure.attack_range_hex]

	if structure.is_under_construction:
		if stats != "":
			stats += "\n"
		stats += "Under Construction"

	stats_label.text = stats

	# Show/hide progress bar for factories
	var is_factory = structure.produces_unit_type != ""
	production_progress.visible = is_factory

	_info_structure = structure

func _process(_delta):
	if _info_structure == null or _info_structure.produces_unit_type == "":
		return
	if not is_instance_valid(_info_structure):
		_info_structure = null
		return
	if _info_structure.is_producing and is_instance_valid(_info_structure.production_timer):
		var t = _info_structure.production_timer
		production_progress.value = (1.0 - t.time_left / t.wait_time) * 100.0
	else:
		production_progress.value = 0.0

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
		if structure.unit_production_enabled == pressed:
			continue
		structure.unit_production_enabled = pressed
		print("Structure %s: Unit production %s" % [structure.display_name, "enabled" if pressed else "disabled"])
		if pressed and not structure.is_producing and not structure.is_waiting_for_resources:
			structure.start_production()
