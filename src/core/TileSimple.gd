class_name TileSimple
extends Tile
# Non-buildable tile: root is a MeshInstance3D. Collision is generated at runtime
# via create_trimesh_collision() in MapGenerator after the mesh is assigned.

func set_overlay_tint(color: Color):
	# The root node itself is the GeometryInstance3D for non-buildable tiles.
	var geo: GeometryInstance3D = get_node(".") as GeometryInstance3D
	if not is_instance_valid(geo):
		return
	if not is_instance_valid(geo.material_overlay):
		geo.material_overlay = StandardMaterial3D.new()
		geo.material_overlay.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		geo.material_overlay.cull_mode = BaseMaterial3D.CULL_DISABLED
	geo.material_overlay.albedo_color = color
