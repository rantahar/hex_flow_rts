extends Node3D
class_name Unit

const HEX_SCALE = 0.6

# Store: player_id (int), hex_x (int), hex_z (int)
@export var mesh: Mesh: set = set_mesh, get = get_mesh # Mesh set externally (from Player)
var _mesh: Mesh # Backing field for mesh
var player_id: int
var hex_x: int
var hex_z: int

var mesh_instance: MeshInstance3D

func _init():
    # Child MeshInstance3D
    mesh_instance = MeshInstance3D.new()
    add_child(mesh_instance)
    mesh_instance.name = "UnitMeshInstance"

func set_mesh(value: Mesh):
    _mesh = value
    if is_instance_valid(mesh_instance):
        mesh_instance.mesh = _mesh

func get_mesh() -> Mesh:
    return _mesh

func initialize(hx: int, hz: int, world_x: float, world_z: float) -> void:
    hex_x = hx
    hex_z = hz
    # Position unit at (world_x, 0.5, world_z)
    position = Vector3(world_x, 0.5, world_z)

func _ready():
    # Child MeshInstance3D with robot model scaled by hex_scale (0.6)
    # Mesh is set in initialization, but applied in _ready or _init if mesh is available
    mesh_instance.scale = Vector3(HEX_SCALE, HEX_SCALE, HEX_SCALE)