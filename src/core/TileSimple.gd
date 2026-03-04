class_name TileSimple
extends Tile
## A non-buildable terrain tile with a simple mesh representation.
##
## Extends the base Tile class for terrain that cannot have structures built on it
## (e.g., water, obstacles). The root node is a MeshInstance3D with collision geometry
## generated at runtime. Inherits formation slots and unit occupancy tracking from
## Tile, but blocks structure placement via the buildable flag.

func set_overlay_tint(color: Color):
	"""
	Applies a color overlay tint to the tile for visual feedback.

	Arguments:
	- color (Color): The color to apply as an overlay.
	"""
	# The root node itself is the GeometryInstance3D for non-buildable tiles.
	var geo: GeometryInstance3D = get_node(".") as GeometryInstance3D
	if not is_instance_valid(geo):
		return
	if not is_instance_valid(geo.material_overlay):
		geo.material_overlay = StandardMaterial3D.new()
		geo.material_overlay.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		geo.material_overlay.cull_mode = BaseMaterial3D.CULL_DISABLED
	geo.material_overlay.albedo_color = color
