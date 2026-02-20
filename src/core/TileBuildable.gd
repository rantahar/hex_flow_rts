class_name TileBuildable
extends Tile

@onready var hole_node: Node3D = $Hole

func set_hole_visibility(_is_visible: bool):
	if is_instance_valid(hole_node):
		hole_node.visible = _is_visible

func set_overlay_tint(color: Color):
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
	if is_instance_valid(hole_node):
		hole_node.visible = false
		for child in hole_node.get_children():
			if child.has_method("set_input_ray_pickable"):
				child.set_input_ray_pickable(false)
