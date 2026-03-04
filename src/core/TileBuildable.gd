class_name TileBuildable
extends Tile
## A buildable terrain tile that supports structure placement.
##
## Extends the base Tile class with buildable-specific visual features. Provides
## functionality for showing/hiding a drill hole visual effect and applying color
## overlays for visual feedback (e.g., valid/invalid placement). Used for terrain
## tiles where structures can be constructed.

@onready var hole_node: Node3D = $Hole

func set_hole_visibility(_is_visible: bool):
	"""
	Shows or hides the drill hole visual effect on this tile.

	Arguments:
	- _is_visible (bool): True to show the hole, false to hide it.
	"""
	if is_instance_valid(hole_node):
		hole_node.visible = _is_visible

func set_overlay_tint(color: Color):
	"""
	Applies a color overlay tint to the tile for visual feedback (e.g., placement validity).

	Arguments:
	- color (Color): The color to apply as an overlay.
	"""
	# TileBuildable is attached to a CSGMesh3D which is a GeometryInstance3D.
	# get_node(".") returns the node untyped so the cast is accepted.
	var geo: GeometryInstance3D = get_node(".") as GeometryInstance3D
	if not is_instance_valid(geo):
		return
	if not is_instance_valid(geo.material_overlay):
		geo.material_overlay = StandardMaterial3D.new()
		geo.material_overlay.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		geo.material_overlay.cull_mode = BaseMaterial3D.CULL_DISABLED
	geo.material_overlay.albedo_color = color

func _ready():
	"""
	Initializes the tile by hiding the drill hole and disabling ray pickable on its children.
	"""
	if is_instance_valid(hole_node):
		hole_node.visible = false
		for child in hole_node.get_children():
			if child.has_method("set_input_ray_pickable"):
				child.set_input_ray_pickable(false)
